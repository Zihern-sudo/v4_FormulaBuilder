/**
 * @Author      WDCi (Zihern)
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
    // Private Constants — compiled once at class load time
    // ─────────────────────────────────────────────────────────────────────────

    /** Matches two consecutive binary operators: AND AND, OR OR, AND OR, etc. */
    private static final Pattern CONSECUTIVE_OPS = Pattern.compile(
        '\\b(AND|OR)\\s+(AND|OR)\\b'
    );

    /**
     * Matches a formula that STARTS with a binary operator used in infix style.
     * Requires whitespace after AND/OR so that the valid function-call forms
     * AND(...) and OR(...) are not matched — those are immediately followed by
     * '(' with no whitespace, so they cannot match '\s+'.
     * Also matches && or || at the very start (no left operand).
     */
    private static final Pattern STARTS_WITH_BINARY = Pattern.compile(
        '^((AND|OR)\\s+|&&|\\|\\|)'
    );

    /** Matches a formula that ends with a logical operator (trailing operator).
     *  Covers word-form AND/OR/NOT as well as symbolic && and || operators. */
    private static final Pattern ENDS_WITH_OP = Pattern.compile(
        '(\\b(AND|OR|NOT)|&&|\\|\\|)\\s*$'
    );

    /**
     * Matches multi-argument function calls where arguments appear to be separated
     * only by whitespace instead of commas, suggesting a missing comma.
     */
    private static final Pattern FUNC_MISSING_COMMA = Pattern.compile(
        '\\b(IF|CASE|INCLUDES|EXCLUDES|LEFT|RIGHT|MID|ROUND|MOD|MAX|MIN|VALUE|TEXT|DATEVALUE|DATETIMEVALUE)'
        + '\\s*\\([^,()]+\\s+[^,()\\s][^,()]*\\)'
    );

    /** Matches doubled or transposed comparison operators: ==, =>, =< */
    private static final Pattern DOUBLE_EQUALS = Pattern.compile('==|=>|=<');

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

            SObject record     = Database.query(query);
            Object  rawValue   = record.get(fieldApiName);
            String  fieldValue = rawValue != null ? String.valueOf(rawValue) : '';

            return new REDU_LightningResponse(true, 'Success', fieldValue);

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
     * @param formulaValue  The new formula string to save to the field; pass an empty
     *                      string to intentionally clear the field value
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
                ' FROM '      + safeObject +
                ' WHERE Id = :recordId' +
                ' LIMIT 1';

            SObject record = Database.query(query);
            record.put(fieldApiName, formulaValue);
            update record;

            return new REDU_LightningResponse(true, 'Update Successful', 'true');

        } catch (QueryException qex) {
            String errorMsg = REDU_ObjectSecurity_UTIL.handleQueryException(qex, false);
            throw REDU_Exception_UTIL.auraException(errorMsg);
        } catch (Exception exp) {
            throw REDU_Exception_UTIL.auraException(exp.getMessage(), exp.getLineNumber(), null);
        }
    }

    /**
     * @description Resolves a target SObject API name by querying a field (or
     *              cross-object relationship path) on the given base object record.
     *
     *              Example call for a one-level cross-object path:
     *                objectApiName = 'reduivy__Study_Scoring_Criteria__c'
     *                fieldPath     = 'reduivy__Study_Scoring_Config__r.reduivy__SObjectType__c'
     *                recordId      = '<criteria record Id>'
     *
     *              fieldPath supports arbitrarily deep relationship traversal
     *              (e.g. 'Parent__r.GrandParent__r.SomeField__c') by splitting
     *              on '.' and walking the SObject chain.
     *
     * @param objectApiName  API name of the base SObject to query
     * @param fieldPath      SOQL field path to select (supports cross-object notation)
     * @param recordId       Id of the record to query
     * @return REDU_LightningResponse whose responseData is a JSON-serialised String or null
     */
    @AuraEnabled(cacheable=true)
    public static REDU_LightningResponse getTargetSObjectType(
        String objectApiName,
        String fieldPath,
        Id     recordId
    ) {
        try {
            validateParams(
                new List<String>{ objectApiName, fieldPath },
                new List<String>{ 'objectApiName', 'fieldPath' }
            );
            if (recordId == null) {
                throw new AuraHandledException('recordId is required.');
            }

            String safeObject = String.escapeSingleQuotes(objectApiName);
            String safeField  = String.escapeSingleQuotes(fieldPath);

            String query =
                'SELECT ' + safeField +
                ' FROM '  + safeObject +
                ' WHERE Id = :recordId' +
                ' LIMIT 1';

            List<SObject> results = Database.query(query);
            if (results.isEmpty()) {
                return new REDU_LightningResponse(true, 'Not found', JSON.serialize(null));
            }

            // Walk the dot-separated path to handle cross-object relationship fields.
            // E.g. 'Parent__r.GrandParent__r.Field__c' → getSObject('Parent__r')
            //        → getSObject('GrandParent__r') → get('Field__c')
            List<String> parts   = fieldPath.split('\\.');
            SObject      current = results[0];
            for (Integer i = 0; i < parts.size() - 1; i++) {
                if (current == null) { break; }
                current = current.getSObject(parts[i]);
            }

            String value = current != null
                ? (String) current.get(parts[parts.size() - 1])
                : null;

            return new REDU_LightningResponse(true, 'Success', JSON.serialize(value));

        } catch (QueryException qex) {
            String errorMsg = REDU_ObjectSecurity_UTIL.handleQueryException(qex, false);
            throw REDU_Exception_UTIL.auraException(errorMsg);
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception exp) {
            throw REDU_Exception_UTIL.auraException(exp.getMessage(), exp.getLineNumber(), null);
        }
    }

    /**
     * @description Returns all accessible fields for the given SObject using
     *              Schema.describeSObjects.  The JS layer decides how to render
     *              each field (label + apiName for the target SObject; apiName only
     *              for standard global variables such as Organization, User, etc.).
     * @param objectApiName API name of the SObject to describe (e.g. Account, Organization)
     * @return REDU_LightningResponse containing a JSON array of {apiName, label} objects
     */
    @AuraEnabled(cacheable=true)
    public static REDU_LightningResponse getObjectFields(String objectApiName) {
        try {
            if (String.isBlank(objectApiName)) {
                throw new AuraHandledException('objectApiName is required.');
            }

            Schema.DescribeSObjectResult[] descResults =
                Schema.describeSObjects(new List<String>{ objectApiName });

            Map<String, Schema.SObjectField> fieldsMap = descResults[0].fields.getMap();
            List<Map<String, String>> fields = new List<Map<String, String>>();

            for (String fieldKey : fieldsMap.keySet()) {
                Schema.DescribeFieldResult dfr = fieldsMap.get(fieldKey).getDescribe();
                fields.add(new Map<String, String>{
                    'apiName' => dfr.getName(),
                    'label'   => dfr.getLabel()
                });
            }

            return new REDU_LightningResponse(true, 'Success', JSON.serialize(fields));

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception exp) {
            throw REDU_Exception_UTIL.auraException(exp.getMessage(), exp.getLineNumber(), null);
        }
    }

    /**
     * @description Retrieves all available Custom Metadata types from the org
     *              by querying EntityDefinition for types ending in '__mdt'
     * @return REDU_LightningResponse containing a List<String> of Custom Metadata type API names
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

            return new REDU_LightningResponse(true, 'Success', JSON.serialize(mdtNames));

        } catch (QueryException qex) {
            String errorMsg = REDU_ObjectSecurity_UTIL.handleQueryException(qex, false);
            throw REDU_Exception_UTIL.auraException(errorMsg);
        } catch (Exception exp) {
            throw REDU_Exception_UTIL.auraException(exp.getMessage(), exp.getLineNumber(), null);
        }
    }

    /**
     * @description Validates the syntax of a formula string.
     *              Does NOT evaluate whether the logical output is true or false.
     *
     *              Checks are performed in two phases:
     *                Phase 1 — A string-literal-aware single-pass character scan that:
     *                   (a) detects unclosed string literals, reporting the exact position;
     *                   (b) counts parenthesis depth only for characters outside string
     *                       literals, so parens embedded in string values are ignored;
     *                   (c) emits a "stripped" copy of the formula with all string literal
     *                       content replaced by a neutral placeholder for Phase 2.
     *                Phase 2 — Pattern-based checks run against the stripped formula
     *                   to detect operator-level syntax errors without false positives
     *                   caused by operator keywords that appear inside string values.
     *
     * @param formula       The formula string to verify
     * @param objectApiName Reserved — API name of the object the formula belongs to
     *                      (not used in the current syntax-only implementation;
     *                      retained for future schema-aware evaluation)
     * @param recordId      Reserved — a sample record Id for future context-aware evaluation
     *                      (not used in the current syntax-only implementation)
     * @return REDU_LightningResponse containing a Map with keys:
     *         isValid (Boolean) and errorMessage (String, null when valid)
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
                return new REDU_LightningResponse(true, 'Verification Result', JSON.serialize(result));
            }

            String trimmed = formula.trim();

            // ─────────────────────────────────────────────────────────────────
            // PHASE 1: String-literal-aware single-pass scan
            //
            // Salesforce formula string literals may use EITHER quote style:
            //   • Single-quoted:  'text value'   ('' = escaped single quote inside)
            //   • Double-quoted:  "text value"   ("" = escaped double quote inside)
            // A quote of one style inside a literal of the other style is treated
            // as ordinary content and does NOT open or close a string.
            // Any character — including (, ), AND, OR — inside a string literal
            // is part of the string value and must be ignored by syntax checks.
            // ─────────────────────────────────────────────────────────────────

            Boolean      insideString    = false;
            String       stringQuoteChar = null; // '\'' or '"' — which quote opened the string
            Integer      parenDepth      = 0;
            Integer      openQuotePos    = -1; // 1-based position of the unclosed opening quote
            List<String> strippedChars   = new List<String>();

            for (Integer i = 0; i < trimmed.length(); i++) {
                String ch = trimmed.substring(i, i + 1);

                if (insideString) {
                    // Inside a string literal — only the MATCHING closing quote ends it.
                    if (ch == stringQuoteChar) {
                        // Two consecutive same-quotes = escaped quote; stay inside the string.
                        if (i + 1 < trimmed.length() && trimmed.substring(i + 1, i + 2) == stringQuoteChar) {
                            i++; // skip the second quote of the escape pair
                            continue;
                        }
                        // Otherwise this is the closing quote — exit string context.
                        insideString    = false;
                        stringQuoteChar = null;
                        openQuotePos    = -1;
                        // Represent the entire string literal as a single space placeholder
                        // so Phase 2 patterns see a neutral token rather than string content.
                        strippedChars.add(' ');
                    }
                    // All other characters inside a string are intentionally skipped.

                } else if (ch == '\'' || ch == '"') {
                    // Opening quote — enter string context, remember which quote style.
                    insideString    = true;
                    stringQuoteChar = ch;
                    openQuotePos    = i + 1; // 1-based for the error message

                } else {
                    // Outside a string: track parenthesis depth and collect for Phase 2.
                    if (ch == '(') {
                        parenDepth++;
                    } else if (ch == ')') {
                        parenDepth--;
                        if (parenDepth < 0) {
                            result.put('isValid',      false);
                            result.put('errorMessage',
                                'Unmatched closing parenthesis at character position ' + (i + 1) + '.');
                            return new REDU_LightningResponse(true, 'Verification Result', JSON.serialize(result));
                        }
                    }
                    strippedChars.add(ch);
                }
            }

            // ── Check A: unclosed string literal ────────────────────────────
            if (insideString) {
                String quoteType = (stringQuoteChar == '"') ? 'double' : 'single';
                result.put('isValid',      false);
                result.put('errorMessage',
                    'Unclosed string literal: the ' + quoteType + ' quote at position ' + openQuotePos +
                    ' was never closed. Ensure every string value is wrapped in a matching pair of ' +
                    quoteType + ' quotes.');
                return new REDU_LightningResponse(true, 'Verification Result', JSON.serialize(result));
            }

            // ── Check B: unbalanced opening parentheses ──────────────────────
            if (parenDepth != 0) {
                result.put('isValid',      false);
                result.put('errorMessage',
                    'Unmatched opening parenthesis: ' + parenDepth +
                    ' parenthesis(es) left unclosed.');
                return new REDU_LightningResponse(true, 'Verification Result', JSON.serialize(result));
            }

            // ─────────────────────────────────────────────────────────────────
            // PHASE 2: Pattern-based operator checks on the stripped formula.
            // String literals have been replaced by single-space placeholders, so
            // none of the patterns below can produce false positives from string content.
            // ─────────────────────────────────────────────────────────────────

            String stripped   = String.join(strippedChars, '');
            String normalized = stripped.replaceAll('\\s+', ' ').trim();
            String upper      = normalized.toUpperCase();

            // ── Check C: consecutive binary operators (AND AND, OR OR, AND OR…) ──
            if (CONSECUTIVE_OPS.matcher(upper).find()) {
                result.put('isValid',      false);
                result.put('errorMessage',
                    'Consecutive logical operators detected (e.g. AND AND, OR OR, AND OR). '
                    + 'Ensure each operator has an operand on both sides.');
                return new REDU_LightningResponse(true, 'Verification Result', JSON.serialize(result));
            }

            // ── Check D: formula starts with a binary operator ───────────────
            if (STARTS_WITH_BINARY.matcher(upper).find()) {
                result.put('isValid',      false);
                result.put('errorMessage',
                    'Formula cannot begin with a binary logical operator (AND / OR). '
                    + 'Add a left-hand operand or remove the leading operator.');
                return new REDU_LightningResponse(true, 'Verification Result', JSON.serialize(result));
            }

            // ── Check E: formula ends with any logical operator ──────────────
            if (ENDS_WITH_OP.matcher(upper).find()) {
                result.put('isValid',      false);
                result.put('errorMessage',
                    'Formula cannot end with a logical operator (AND / OR / NOT). '
                    + 'Add a right-hand operand or remove the trailing operator.');
                return new REDU_LightningResponse(true, 'Verification Result', JSON.serialize(result));
            }

            // ── Check F: missing comma inside multi-argument function calls ───
            if (FUNC_MISSING_COMMA.matcher(upper).find()) {
                result.put('isValid',      false);
                result.put('errorMessage',
                    'Possible missing comma inside a function call. '
                    + 'Ensure all function arguments are separated by commas.');
                return new REDU_LightningResponse(true, 'Verification Result', JSON.serialize(result));
            }

            // ── Check G: doubled / invalid comparison operators (==, =>, =<) ─
            if (DOUBLE_EQUALS.matcher(normalized).find()) {
                result.put('isValid',      false);
                result.put('errorMessage',
                    'Invalid operator detected. Use = for equality and != or <> for not-equal. '
                    + 'Remove any doubled operators (==, =>, =<).');
                return new REDU_LightningResponse(true, 'Verification Result', JSON.serialize(result));
            }

            // ── All checks passed ────────────────────────────────────────────
            return new REDU_LightningResponse(true, 'Success', JSON.serialize(result));

        } catch (Exception exp) {
            throw REDU_Exception_UTIL.auraException(exp.getMessage(), exp.getLineNumber(), null);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private Helpers
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Validates that a list of String parameters are non-blank,
     *              throwing AuraHandledException for the first blank value found
     * @param values     List of String values to validate
     * @param paramNames Matching list of parameter names used in the error message
     */
    private static void validateParams(List<String> values, List<String> paramNames) {
        for (Integer i = 0; i < values.size(); i++) {
            if (String.isBlank(values[i])) {
                throw new AuraHandledException(
                    paramNames[i] + ' is required and cannot be blank.'
                );
            }
        }
    }
}
