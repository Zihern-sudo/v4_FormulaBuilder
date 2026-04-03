/**
 * @Author      WDCi ()
 * @Date        April 2026
 * @group       Formula Builder
 * @Description Apex controller for the formulaBuilder LWC. Handles field value
 *              retrieval, formula updates, custom metadata type lookups, and
 *              formula syntax verification.
 * @changehistory
 * ISS-002768 2026-04-03 - Initial development of Formula Builder Apex Controller
 */
public with sharing class REDU_FormulaBuilder_LCTRL {

    // ─────────────────────────────────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────────────────────────────────

    private static final String OPERATOR_AND  = 'AND';
    private static final String OPERATOR_OR   = 'OR';
    private static final String OPERATOR_NOT  = 'NOT';

    // ─────────────────────────────────────────────────────────────────────────
    // Public AuraEnabled Methods
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Retrieves the current formula value of a specified field on a given record
     * @param objectApiName API name of the Salesforce object (e.g. Study_Requirement_Set__c)
     * @param fieldApiName  API name of the formula field to retrieve (e.g. Criteria__c)
     * @param recordId      The Salesforce record Id to retrieve the field value from
     * @return REDU_LightningResponse wrapping the field value String
     */
    @AuraEnabled(cacheable=true)
    public static REDU_LightningResponse getFieldValue(
        String objectApiName,
        String fieldApiName,
        Id recordId
    ) {
        try {
            validateParams(
                new List<String>{ objectApiName, fieldApiName },
                new List<String>{ 'objectApiName', 'fieldApiName' }
            );
            if (recordId == null) {
                throw new AuraHandledException('recordId is required.');
            }

            String safeObject = String.escapeSingleQuotes(objectApiName);
            String safeField  = String.escapeSingleQuotes(fieldApiName);

            String query =
                'SELECT ' + safeField +
                ' FROM '  + safeObject +
                ' WHERE Id = :recordId' +
                ' LIMIT 1';

            SObject record = Database.query(query);
            Object rawValue = record.get(fieldApiName);
            String fieldValue = rawValue != null ? String.valueOf(rawValue) : '';

            return new REDU_LightningResponse(fieldValue);

        } catch (QueryException qex) {
            String errorMsg = REDU_ObjectSecurity_UTIL.handleQueryException(qex, false);
            throw REDU_Exception_UTIL.auraException(errorMsg);
        } catch (Exception exp) {
            throw REDU_Exception_UTIL.auraException(exp.getMessage(), exp.getLineNumber(), null);
        }
    }

    /**
     * @description Updates a specified field on a given record with the new formula string
     * @param objectApiName API name of the Salesforce object
     * @param fieldApiName  API name of the field to update
     * @param recordId      The Salesforce record Id to update
     * @param formulaValue  The new formula string to save to the field
     * @return REDU_LightningResponse confirming the update
     */
    @AuraEnabled
    public static REDU_LightningResponse updateFieldValue(
        String objectApiName,
        String fieldApiName,
        Id recordId,
        String formulaValue
    ) {
        try {
            validateParams(
                new List<String>{ objectApiName, fieldApiName },
                new List<String>{ 'objectApiName', 'fieldApiName' }
            );
            if (recordId == null) {
                throw new AuraHandledException('recordId is required.');
            }

            String safeObject = String.escapeSingleQuotes(objectApiName);
            String safeField  = String.escapeSingleQuotes(fieldApiName);

            String query =
                'SELECT Id, ' + safeField +
                ' FROM '  + safeObject +
                ' WHERE Id = :recordId' +
                ' LIMIT 1';

            SObject record = Database.query(query);
            record.put(fieldApiName, formulaValue);

            update record;

            return new REDU_LightningResponse(true);

        } catch (QueryException qex) {
            String errorMsg = REDU_ObjectSecurity_UTIL.handleQueryException(qex, false);
            throw REDU_Exception_UTIL.auraException(errorMsg);
        } catch (Exception exp) {
            throw REDU_Exception_UTIL.auraException(exp.getMessage(), exp.getLineNumber(), null);
        }
    }

    /**
     * @description Retrieves all available Custom Metadata types from the org
     *              by querying EntityDefinition for types ending in '__mdt'
     * @return REDU_LightningResponse containing a List<String> of CustomMetadata type API names
     */
    @AuraEnabled(cacheable=true)
    public static REDU_LightningResponse getCustomMetadataTypes() {
        try {
            List<EntityDefinition> entities = [
                SELECT QualifiedApiName
                FROM   EntityDefinition
                WHERE  QualifiedApiName LIKE '%__mdt'
                ORDER BY QualifiedApiName ASC
            ];

            List<String> mdtNames = new List<String>();
            for (EntityDefinition ed : entities) {
                mdtNames.add(ed.QualifiedApiName);
            }

            return new REDU_LightningResponse(mdtNames);

        } catch (QueryException qex) {
            String errorMsg = REDU_ObjectSecurity_UTIL.handleQueryException(qex, false);
            throw REDU_Exception_UTIL.auraException(errorMsg);
        } catch (Exception exp) {
            throw REDU_Exception_UTIL.auraException(exp.getMessage(), exp.getLineNumber(), null);
        }
    }

    /**
     * @description Validates the syntax of a formula string against a sample record.
     *              Checks for missing commas, unmatched parentheses, and invalid operators.
     *              Does NOT evaluate whether the logical output is true or false.
     * @param formula       The formula string to verify
     * @param objectApiName API name of the object the formula belongs to
     * @param recordId      A sample record Id to use for context during verification
     * @return REDU_LightningResponse containing isValid (Boolean) and errorMessage (String)
     */
    @AuraEnabled
    public static REDU_LightningResponse verifyFormula(
        String formula,
        String objectApiName,
        Id recordId
    ) {
        try {
            Map<String, Object> result = new Map<String, Object>{
                'isValid'      => true,
                'errorMessage' => null
            };

            // ── Guard: empty formula ─────────────────────────────────────────
            if (String.isBlank(formula)) {
                result.put('isValid',      false);
                result.put('errorMessage', 'Formula cannot be empty.');
                return new REDU_LightningResponse(result);
            }

            String trimmed    = formula.trim();
            String normalized = trimmed.replaceAll('\\s+', ' ');
            String upper      = normalized.toUpperCase();

            // ── Check 1: Balanced parentheses ───────────────────────────────
            Integer depth = 0;
            for (Integer i = 0; i < trimmed.length(); i++) {
                String ch = trimmed.substring(i, i + 1);
                if (ch == '(') {
                    depth++;
                } else if (ch == ')') {
                    depth--;
                    if (depth < 0) {
                        result.put('isValid',      false);
                        result.put('errorMessage',
                            'Unmatched closing parenthesis at character position ' + (i + 1) + '.');
                        return new REDU_LightningResponse(result);
                    }
                }
            }
            if (depth != 0) {
                result.put('isValid',      false);
                result.put('errorMessage',
                    'Unmatched opening parenthesis: ' + depth + ' parenthesis(es) left unclosed.');
                return new REDU_LightningResponse(result);
            }

            // ── Check 2: Consecutive binary operators (AND AND, OR OR, AND OR, etc.) ──
            Pattern consecutiveOps = Pattern.compile('\\b(AND|OR)\\s+(AND|OR)\\b');
            if (consecutiveOps.matcher(upper).find()) {
                result.put('isValid',      false);
                result.put('errorMessage',
                    'Consecutive logical operators detected (e.g. AND AND, OR OR, AND OR). '
                    + 'Ensure each operator has an operand on both sides.');
                return new REDU_LightningResponse(result);
            }

            // ── Check 3: Formula starts with a binary operator ───────────────
            Pattern startsWithBinary = Pattern.compile('^(AND|OR)\\b');
            if (startsWithBinary.matcher(upper).find()) {
                result.put('isValid',      false);
                result.put('errorMessage',
                    'Formula cannot begin with a binary logical operator (AND / OR). '
                    + 'Add a left-hand operand or remove the leading operator.');
                return new REDU_LightningResponse(result);
            }

            // ── Check 4: Formula ends with any operator (AND, OR, NOT) ──────
            Pattern endsWithOp = Pattern.compile('\\b(AND|OR|NOT)\\s*$');
            if (endsWithOp.matcher(upper).find()) {
                result.put('isValid',      false);
                result.put('errorMessage',
                    'Formula cannot end with a logical operator (AND / OR / NOT). '
                    + 'Add a right-hand operand or remove the trailing operator.');
                return new REDU_LightningResponse(result);
            }

            // ── Check 5: Missing comma inside multi-argument function calls ──
            // Matches patterns like: FUNCTIONNAME(argA argB) with no comma between args
            Pattern funcMissingComma = Pattern.compile(
                '\\b(IF|CASE|INCLUDES|EXCLUDES|LEFT|RIGHT|MID|ROUND|MOD|MAX|MIN|VALUE|TEXT|DATEVALUE|DATETIMEVALUE)' +
                '\\s*\\([^,()]+\\s+[^,()\\s][^,()]*\\)'
            );
            if (funcMissingComma.matcher(upper).find()) {
                result.put('isValid',      false);
                result.put('errorMessage',
                    'Possible missing comma inside a function call. '
                    + 'Ensure all function arguments are separated by commas.');
                return new REDU_LightningResponse(result);
            }

            // ── Check 6: Double comparison operators (e.g. == or =>) ────────
            Pattern doubleEquals = Pattern.compile('==|=>|=<|<>(?!=)');
            if (doubleEquals.matcher(normalized).find()) {
                result.put('isValid',      false);
                result.put('errorMessage',
                    'Invalid operator detected. Use = for equality, != for not-equal, '
                    + '<> is also valid for not-equal. Remove any doubled operators (==, =>, =<).');
                return new REDU_LightningResponse(result);
            }

            return new REDU_LightningResponse(result);

        } catch (QueryException qex) {
            String errorMsg = REDU_ObjectSecurity_UTIL.handleQueryException(qex, false);
            throw REDU_Exception_UTIL.auraException(errorMsg);
        } catch (Exception exp) {
            throw REDU_Exception_UTIL.auraException(exp.getMessage(), exp.getLineNumber(), null);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private Helpers
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Validates that a list of string parameters are non-blank
     * @param values     List of string values to validate
     * @param paramNames Matching list of parameter names used in the error message
     */
    private static void validateParams(List<String> values, List<String> paramNames) {
        for (Integer i = 0; i < values.size(); i++) {
            if (String.isBlank(values[i])) {
                throw new AuraHandledException(paramNames[i] + ' is required and cannot be blank.');
            }
        }
    }
}
