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

            // Guard: if objectApiName still contains the '{...}' dynamic syntax it has
            // not been resolved yet — return empty rather than crashing SOQL.
            if (objectApiName.trim().startsWith('{')) {
                return new REDU_LightningResponse(true, 'Pending Resolution', '');
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
    // Not cacheable — we need fresh data per record and cacheable=true has stricter
    // platform restrictions that can cause ID binding failures with dynamic SOQL.
    @AuraEnabled
    public static REDU_LightningResponse getTargetSObjectType(
        String objectApiName,
        String fieldPath,
        String recordId          // String (not Id) to avoid platform type-binding edge cases
    ) {
        try {
            if (String.isBlank(objectApiName)) {
                return new REDU_LightningResponse(false, 'objectApiName is required.', null);
            }
            if (String.isBlank(fieldPath)) {
                return new REDU_LightningResponse(false, 'fieldPath is required.', null);
            }
            if (String.isBlank(recordId)) {
                return new REDU_LightningResponse(false, 'recordId is required.', null);
            }

            Id     safeId    = (Id) recordId;
            String safeObj   = String.escapeSingleQuotes(objectApiName.trim());
            String safeField = String.escapeSingleQuotes(fieldPath.trim());

            String query =
                'SELECT ' + safeField +
                ' FROM '  + safeObj   +
                ' WHERE Id = :safeId'  +
                ' LIMIT 1';

            List<SObject> results = Database.query(query);
            if (results.isEmpty()) {
                return new REDU_LightningResponse(true, 'Record not found', JSON.serialize(null));
            }

            // Walk the dot-separated path to handle cross-object relationship fields.
            // E.g. 'Parent__r.GrandParent__r.Field__c' → getSObject('Parent__r')
            //        → getSObject('GrandParent__r') → get('Field__c')
            List<String> parts   = fieldPath.trim().split('\\.');
            SObject      current = results[0];
            for (Integer i = 0; i < parts.size() - 1; i++) {
                if (current == null) { break; }
                current = current.getSObject(parts[i].trim());
            }

            Object rawValue = current != null ? current.get(parts[parts.size() - 1].trim()) : null;
            String value    = rawValue != null ? String.valueOf(rawValue) : null;

            return new REDU_LightningResponse(true, 'Success', JSON.serialize(value));

        } catch (System.QueryException qex) {
            // On a bad field/column name, describe the object's String fields so the
            // admin can identify the correct API name from the error toast.
            String fieldHint = '';
            try {
                String baseObj = objectApiName != null ? objectApiName.trim() : '';
                // For cross-object paths, the last segment object is unknown — describe base.
                Schema.DescribeSObjectResult[] dr = Schema.describeSObjects(new List<String>{ baseObj });
                Map<String, Schema.SObjectField> fm = dr[0].fields.getMap();
                List<String> textFields = new List<String>();
                for (String key : fm.keySet()) {
                    Schema.DescribeFieldResult dfr = fm.get(key).getDescribe();
                    Schema.DisplayType dt = dfr.getType();
                    if (dt == Schema.DisplayType.STRING || dt == Schema.DisplayType.TEXTAREA
                            || dt == Schema.DisplayType.PICKLIST || dt == Schema.DisplayType.REFERENCE) {
                        textFields.add(dfr.getName());
                    }
                }
                textFields.sort();
                if (!textFields.isEmpty()) {
                    fieldHint = ' Available text/picklist/lookup fields on ' + baseObj + ': '
                              + String.join(textFields, ', ') + '.';
                }
            } catch (Exception descEx) {
                // ignore describe failure — just omit the fieldHint
            }
            return new REDU_LightningResponse(
                false,
                qex.getMessage() + fieldHint,
                null
            );
        } catch (Exception exp) {
            // Return error as a non-success response so JS can show the exact message.
            // This avoids a silent fallback and makes misconfiguration diagnosable.
            return new REDU_LightningResponse(
                false,
                exp.getTypeName() + ': ' + exp.getMessage(),
                null
            );
        }
    }

    /**
     * @description Returns all accessible fields for the given SObject.
     *              For recognised global system variable seeds (User, Organization, etc.)
     *              a curated hardcoded list is returned instead of a live Schema describe,
     *              because these are virtual objects that do not have a queryable schema
     *              in all contexts.  For all other SObjects the live describe is used.
     * @param objectApiName API name of the SObject or system-variable seed
     *                      (e.g. 'Account', 'User', '$User', 'Organization')
     * @return REDU_LightningResponse containing a JSON array of {apiName, label} objects
     */
    @AuraEnabled(cacheable=true)
    public static REDU_LightningResponse getObjectFields(String objectApiName) {
        try {
            if (String.isBlank(objectApiName)) {
                throw new AuraHandledException('objectApiName is required.');
            }

            List<Map<String, String>> fields = new List<Map<String, String>>();

            // Strip optional '$' prefix (e.g. '$User' → 'User') so callers can pass
            // either form and the lookup works consistently.
            String cleanKey = objectApiName.replace('$', '');

            Map<String, List<String>> systemVariableMap = getSystemVariableFieldsMap();

            if (systemVariableMap.containsKey(cleanKey)) {
                // System variable seed — return curated list; label matches API name
                // because these fields are referenced by API name in formula expressions.
                for (String fieldName : systemVariableMap.get(cleanKey)) {
                    fields.add(new Map<String, String>{
                        'apiName' => fieldName,
                        'label'   => fieldName
                    });
                }
            } else {
                // Standard SObject — perform a live Schema describe.
                Schema.DescribeSObjectResult[] descResults =
                    Schema.describeSObjects(new List<String>{ objectApiName });
                Map<String, Schema.SObjectField> fieldsMap = descResults[0].fields.getMap();

                for (String fieldKey : fieldsMap.keySet()) {
                    Schema.DescribeFieldResult dfr = fieldsMap.get(fieldKey).getDescribe();
                    fields.add(new Map<String, String>{
                        'apiName' => dfr.getName(),
                        'label'   => dfr.getLabel()
                    });
                }
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
     * @description Validates a formula string against a specific return type or auto-detects it.
     *              Supports all FormulaEval.FormulaReturnType values by mapping UI-friendly
     *              labels (Checkbox, Text, Number, Currency, Percent) to the corresponding
     *              internal enum names and back again for consistent messaging.
     *
     *              Round 1 — Syntax & return-type detection via FormulaEval compiler.
     *              Round 2 — Smart runtime evaluation against a real record so that
     *              data-dependent errors are also surfaced before save.
     *
     * @param formulaStr         The formula string to verify (named to avoid shadowing
     *                           the Formula builder class — Apex is case-insensitive)
     * @param objectApiName      API name of the SObject the formula is evaluated against
     * @param recordId           Id of the record providing runtime context; may be null
     *                           (compile-only validation is still performed)
     * @param expectedReturnType Optional UI-friendly return type label (e.g. 'Checkbox',
     *                           'Text', 'Number', 'Currency', 'Percent', or a raw enum
     *                           name such as 'Date').  Pass null to auto-detect.
     * @return REDU_LightningResponse containing a Map with keys:
     *         isValid (Boolean), errorMessage (String), matchedType (String)
     */
    @AuraEnabled
    public static REDU_LightningResponse verifyFormula(
        String formulaStr,
        String objectApiName,
        Id recordId,
        String expectedReturnType
    ) {
        try {
            Map<String, Object> result = new Map<String, Object>{
                'isValid'      => true,
                'errorMessage' => null,
                'matchedType'  => null
            };

            if (String.isBlank(formulaStr) || String.isBlank(objectApiName)) {
                result.put('isValid', false);
                result.put('errorMessage', 'Formula and Object API Name are required.');
                return new REDU_LightningResponse(true, 'Verification Result', JSON.serialize(result));
            }

            // ── Step 0: Context Auto-Resolution ──────────────────────────────
            // Determine the effective SObject for compilation.  If the record on
            // screen is a config record (not the formula's target object), try to
            // read the target SObject type from a dedicated field so that field
            // references in the formula are validated against the correct schema.
            String effectiveObjectApiName = objectApiName.trim();

            if (recordId != null) {
                String currentRecordType = recordId.getSObjectType().getDescribe().getName();

                if (currentRecordType != effectiveObjectApiName) {
                    try {
                        // Best-effort: query the config record for a field that
                        // stores the target SObject type.  Silently ignored if the
                        // field does not exist on this object.
                        String configQuery =
                            'SELECT reduivy__SObject_Type__c' +
                            ' FROM ' + currentRecordType +
                            ' WHERE Id = :recordId LIMIT 1';
                        SObject configRec      = Database.query(configQuery);
                        String  resolvedTarget = (String) configRec.get('reduivy__SObject_Type__c');

                        if (String.isNotBlank(resolvedTarget)) {
                            effectiveObjectApiName = resolvedTarget;
                        }
                    } catch (Exception ignoreEx) {
                        // Field not present on this object — keep original objectApiName.
                    }
                }
            }

            // ── Resolve SObject type ─────────────────────────────────────────
            Schema.SObjectType sobjType = Schema.getGlobalDescribe().get(effectiveObjectApiName);
            if (sobjType == null) {
                result.put('isValid', false);
                result.put('errorMessage', 'SObject not found: ' + effectiveObjectApiName);
                return new REDU_LightningResponse(true, 'Verification Result', JSON.serialize(result));
            }

            // ── Round 1: Syntax & Return Type Detection ───────────────────────
            // Formula.builder().build() performs full syntax + schema validation.
            // We either try only the requested return type (strict check) or iterate
            // all available types to auto-detect (permissive check).
            Boolean isStrictTypeCheck = String.isNotBlank(expectedReturnType);
            List<FormulaEval.FormulaReturnType> typesToCheck = new List<FormulaEval.FormulaReturnType>();

            if (isStrictTypeCheck) {
                // Map friendly UI label → internal enum name.
                // 'Number', 'Currency', 'Percent' all map to the Decimal enum constant.
                String internalName = expectedReturnType;
                if      (expectedReturnType.equalsIgnoreCase('Checkbox'))  { internalName = 'Boolean'; }
                else if (expectedReturnType.equalsIgnoreCase('Text'))      { internalName = 'String';  }
                else if (expectedReturnType.equalsIgnoreCase('Number')
                      || expectedReturnType.equalsIgnoreCase('Currency')
                      || expectedReturnType.equalsIgnoreCase('Percent'))   { internalName = 'Decimal'; }

                for (FormulaEval.FormulaReturnType rt : FormulaEval.FormulaReturnType.values()) {
                    if (rt.name().equalsIgnoreCase(internalName)) {
                        typesToCheck.add(rt);
                    }
                }
            } else {
                typesToCheck = FormulaEval.FormulaReturnType.values();
            }

            FormulaEval.FormulaInstance builtFormula = null;
            String lastError = null;

            for (FormulaEval.FormulaReturnType rt : typesToCheck) {
                try {
                    builtFormula = Formula.builder()
                        .withReturnType(rt)
                        .withType(sobjType)
                        .withFormula(formulaStr.trim())
                        .build();

                    // Reverse-map enum name → friendly UI label for consistent messaging.
                    String prettyName;
                    if (rt.name().equalsIgnoreCase('Boolean')) {
                        prettyName = 'Checkbox';
                    } else if (rt.name().equalsIgnoreCase('String')) {
                        prettyName = 'Text';
                    } else if (rt.name().equalsIgnoreCase('Decimal') || rt.name().equalsIgnoreCase('Double')) {
                        // Preserve the admin's specific choice (Currency/Percent) if provided;
                        // otherwise default to the generic 'Number' label.
                        prettyName = isStrictTypeCheck ? expectedReturnType : 'Number';
                    } else {
                        // Date, DateTime, Id, Time — capitalise properly.
                        prettyName = rt.name().toLowerCase().capitalize();
                        if (prettyName.equalsIgnoreCase('Datetime')) { prettyName = 'DateTime'; }
                    }

                    result.put('matchedType', prettyName);
                    break;
                } catch (Exception e) {
                    lastError = e.getMessage();
                }
            }

            if (builtFormula == null) {
                result.put('isValid', false);
                String errorPrefix = isStrictTypeCheck
                    ? 'Formula does not return ' + expectedReturnType + ': '
                    : 'Compilation Error: ';
                result.put('errorMessage', errorPrefix + lastError);
                return new REDU_LightningResponse(true, 'Verification Result', JSON.serialize(result));
            }

            // ── Round 2: Smart Runtime Evaluation ────────────────────────────
            // Evaluate the compiled formula against a real record so that
            // data-dependent errors are also caught before the formula is saved.
            if (recordId != null) {
                try {
                    Id     actualEvalId      = recordId;
                    String providedRecordType = recordId.getSObjectType().getDescribe().getName();

                    // If the provided record is a config record (not the target
                    // object), fetch a sample record of the target object instead.
                    if (providedRecordType != effectiveObjectApiName) {
                        List<SObject> samples = Database.query(
                            'SELECT Id FROM ' + effectiveObjectApiName + ' LIMIT 1'
                        );
                        if (!samples.isEmpty()) { actualEvalId = samples[0].Id; }
                    }

                    Set<String> fields = builtFormula.getReferencedFields();
                    fields.add('Id');

                    String evalQuery =
                        'SELECT ' + String.join(new List<String>(fields), ', ') +
                        ' FROM '  + effectiveObjectApiName +
                        ' WHERE Id = :actualEvalId LIMIT 1';

                    SObject targetRecord = Database.query(evalQuery);
                    if (targetRecord != null) {
                        builtFormula.evaluate(targetRecord);
                    }
                } catch (Exception e) {
                    result.put('isValid', false);
                    result.put('errorMessage', 'Runtime Error: ' + e.getMessage());
                    return new REDU_LightningResponse(true, 'Verification Result', JSON.serialize(result));
                }
            }

            String successMsg = 'Formula syntax is valid. (Return Type: ' + result.get('matchedType') + ')';
            return new REDU_LightningResponse(true, successMsg, JSON.serialize(result));

        } catch (Exception exp) {
            throw REDU_Exception_UTIL.auraException(exp.getMessage(), exp.getLineNumber(), null);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private Helpers
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Curated mapping of global system-variable seeds to the fields
     *              that are valid in Salesforce formula expressions.
     *              These are virtual objects: describeSObjects() does not reliably
     *              return them in all org contexts, so the list is maintained here.
     * @return Map of seed name (without '$') → List of supported field API names
     */
    private static Map<String, List<String>> getSystemVariableFieldsMap() {
        return new Map<String, List<String>>{
            'Organization' => new List<String>{
                'Address', 'City', 'Country', 'Division', 'Fax', 'GeocodeAccuracy',
                'GoogleAppsDomain', 'Latitude', 'Longitude', 'Name', 'OrganizationId',
                'Phone', 'PostalCode', 'State', 'Street', 'UiSkin'
            },
            'Profile' => new List<String>{
                'CreatedById', 'CreatedDate', 'Description', 'Id', 'LastModifiedById',
                'LastModifiedDate', 'ManageUsers', 'Name', 'UsageType', 'UserType'
            },
            'Setup.reduivy__RIO_Education_Ivy_Settings__c' => new List<String>{
                'reduivy__Academic_Profile_Generation_Type__c',
                'reduivy__Academic_Profile_Identifier_Mapping__c',
                'reduivy__Academic_Profile_Name_Format__c',
                'reduivy__Academic_Term_Apply_FA_Batch_Size__c',
                'reduivy__Academic_Term_Generate_Orders_Batch_Size__c',
                'reduivy__Administrative_Account_Name_Format__c',
                'reduivy__Debug_Mode__c',
                'reduivy__Default_Owner_Id__c'
            },
            'System' => new List<String>{ 'OriginDateTime' },
            'User' => new List<String>{
                'Alias', 'City', 'CompanyName', 'ContactId', 'Country', 'Department',
                'Division', 'Email', 'EmailSignature', 'EmployeeNumber', 'EndOfDay',
                'Extension', 'Fax', 'FederationIdentifier', 'FirstName', 'GeocodeAccuracy',
                'Id', 'IsActive', 'LanguageLocaleKey', 'LastName', 'Latitude',
                'LocaleSidKey', 'Longitude', 'ManagerId', 'MobilePhone', 'CommunityNickname',
                'Phone', 'PostalCode', 'ProfileId', 'StartOfDay', 'State', 'Street',
                'TimeZoneSidKey', 'Title', 'UserPreferencesUiTheme',
                'UserPreferencesUiThemeDisplayed', 'UserRoleId', 'UserType', 'Username'
            },
            'UserRole' => new List<String>{
                'CaseAccessForAccountOwner', 'ContactAccessForAccountOwner', 'Description',
                'DeveloperName', 'Id', 'LastModifiedById', 'LastModifiedDate',
                'MayForecastManagerShare', 'Name', 'OpportunityAccessForAccountOwner',
                'PortalRole', 'PortalType'
            }
        };
    }

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
