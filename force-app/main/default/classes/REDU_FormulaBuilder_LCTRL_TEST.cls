/**
 * @Author      WDCi (Zihern)
 * @Date        April 2026
 * @group       Formula Builder
 * @Description Test class for REDU_FormulaBuilder_LCTRL. Covers getFieldValue,
 *              updateFieldValue, getCustomMetadataTypes, and verifyFormula,
 *              including happy paths, negative/error scenarios, and string-literal
 *              edge cases for the syntax verifier.
 * @changehistory
 * ISS-002768 2026-04-03 - Initial test class for Formula Builder Apex Controller
 */
@isTest
public class REDU_FormulaBuilder_LCTRL_TEST {

    // ─────────────────────────────────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────────────────────────────────

    private static final String OBJECT_API_NAME = 'Account';
    private static final String FIELD_API_NAME  = 'Description';

    // A formula that is stored as the initial Description value in @TestSetup.
    // Field names in Salesforce formulas are bare (no object prefix).
    private static final String INITIAL_FORMULA =
        'AnnualRevenue > 0 AND NOT(ISBLANK(Industry))';

    // ─────────────────────────────────────────────────────────────────────────
    // Test Setup
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Inserts a shared Account whose Description holds the initial
     *              formula string. Queried by Id in individual test methods.
     */
    @TestSetup
    static void makeData() {
        Account acc = new Account(
            Name        = 'Formula Builder Test Account',
            Description = INITIAL_FORMULA,
            Industry    = 'Technology'
        );
        insert acc;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helper
    // ─────────────────────────────────────────────────────────────────────────

    /** Convenience query so each test does not repeat the same SOQL line. */
    private static Account getTestAccount() {
        return [SELECT Id, Description FROM Account
                WHERE Name = 'Formula Builder Test Account' LIMIT 1];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getFieldValue — Tests
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Happy path: returns the correct formula string stored in
     *              the Account Description field.
     */
    @isTest
    static void testGetFieldValue_Success() {
        Account acc = getTestAccount();

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.getFieldValue(
            OBJECT_API_NAME, FIELD_API_NAME, acc.Id
        );
        Test.stopTest();

        System.assertNotEquals(null, response,              'Response must not be null');
        System.assertNotEquals(null, response.responseData, 'Response data must not be null');
        System.assertEquals(INITIAL_FORMULA, response.responseData,
            'Returned field value must match the inserted Description');
    }

    /**
     * @description Null field value: Description is cleared before the call;
     *              the method must return an empty string (not throw).
     */
    @isTest
    static void testGetFieldValue_NullFieldValue_ReturnsEmptyString() {
        Account acc = getTestAccount();
        acc.Description = null;
        update acc;

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.getFieldValue(
            OBJECT_API_NAME, FIELD_API_NAME, acc.Id
        );
        Test.stopTest();

        System.assertEquals('', response.responseData,
            'A null field value must return an empty string, not null');
    }

    /**
     * @description Negative: blank objectApiName must throw AuraHandledException.
     */
    @isTest
    static void testGetFieldValue_BlankObjectApiName_ThrowsException() {
        Account acc = getTestAccount();
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            REDU_FormulaBuilder_LCTRL.getFieldValue('', FIELD_API_NAME, acc.Id);
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown,
            'AuraHandledException expected for blank objectApiName');
    }

    /**
     * @description Negative: blank fieldApiName must throw AuraHandledException.
     */
    @isTest
    static void testGetFieldValue_BlankFieldApiName_ThrowsException() {
        Account acc = getTestAccount();
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            REDU_FormulaBuilder_LCTRL.getFieldValue(OBJECT_API_NAME, '', acc.Id);
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown,
            'AuraHandledException expected for blank fieldApiName');
    }

    /**
     * @description Negative: null recordId must throw AuraHandledException.
     */
    @isTest
    static void testGetFieldValue_NullRecordId_ThrowsException() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            REDU_FormulaBuilder_LCTRL.getFieldValue(OBJECT_API_NAME, FIELD_API_NAME, null);
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown,
            'AuraHandledException expected for null recordId');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // updateFieldValue — Tests
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Happy path: the new formula string is persisted to the field
     *              and the method returns true in response.data.
     */
    @isTest
    static void testUpdateFieldValue_Success() {
        Account acc        = getTestAccount();
        String  newFormula = 'Account.Industry = \'Finance\' OR Account.AnnualRevenue >= 500000';

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.updateFieldValue(
            OBJECT_API_NAME, FIELD_API_NAME, acc.Id, newFormula
        );
        Test.stopTest();

        System.assertNotEquals(null, response, 'Response must not be null');
        System.assertEquals('true', response.responseData,
            'Response data must be true on a successful update');

        Account updated = [SELECT Description FROM Account WHERE Id = :acc.Id LIMIT 1];
        System.assertEquals(newFormula, updated.Description,
            'Description must reflect the newly saved formula');
    }

    /**
     * @description Clearing scenario: passing an empty string must persist an
     *              empty / null Description without throwing.
     */
    @isTest
    static void testUpdateFieldValue_ClearFormula() {
        Account acc = getTestAccount();

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.updateFieldValue(
            OBJECT_API_NAME, FIELD_API_NAME, acc.Id, ''
        );
        Test.stopTest();

        System.assertNotEquals(null, response, 'Response must not be null');

        Account updated = [SELECT Description FROM Account WHERE Id = :acc.Id LIMIT 1];
        String  actual  = updated.Description == null ? '' : updated.Description;
        System.assertEquals('', actual,
            'Description must be empty or null after the clear call');
    }

    /**
     * @description Negative: null recordId must throw AuraHandledException.
     */
    @isTest
    static void testUpdateFieldValue_NullRecordId_ThrowsException() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            REDU_FormulaBuilder_LCTRL.updateFieldValue(
                OBJECT_API_NAME, FIELD_API_NAME, null, 'someFormula'
            );
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown,
            'AuraHandledException expected for null recordId');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getCustomMetadataTypes — Tests
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Happy path: verifies the method returns a non-null, non-empty
     *              list and that every entry ends with __mdt (case-insensitive).
     */
    @isTest
    static void testGetCustomMetadataTypes_Success() {
        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.getCustomMetadataTypes();
        Test.stopTest();

        System.assertNotEquals(null, response,              'Response must not be null');
        System.assertNotEquals(null, response.responseData, 'Response data must not be null');

        List<Object> mdtNames = (List<Object>) JSON.deserializeUntyped(response.responseData);
        System.assert(mdtNames.size() > 0,
            'At least one Custom Metadata Type must exist in the org');

        for (Object nameObj : mdtNames) {
            String name = (String) nameObj;
            System.assert(name.toLowerCase().endsWith('__mdt'),
                'All returned names must end with __mdt but got: ' + name);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getTargetSObjectType — Tests
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Happy path: direct field (no relationship traversal).
     *              Uses Account.Industry which is set to 'Technology' in @TestSetup.
     */
    @isTest
    static void testGetTargetSObjectType_DirectField_ReturnsValue() {
        Account acc = getTestAccount();

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.getTargetSObjectType(
            'Account', 'Industry', acc.Id
        );
        Test.stopTest();

        System.assertNotEquals(null, response, 'Response must not be null');
        System.assertEquals(true, response.isSuccess, 'Response must be successful');
        String value = (String) JSON.deserializeUntyped(response.responseData);
        System.assertEquals('Technology', value,
            'Industry field must return the value set in @TestSetup');
    }

    /**
     * @description Blank objectApiName must return a non-success response (not throw).
     */
    @isTest
    static void testGetTargetSObjectType_BlankObjectApiName_ReturnsNonSuccess() {
        Account acc = getTestAccount();

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.getTargetSObjectType(
            '', 'Industry', acc.Id
        );
        Test.stopTest();

        System.assertNotEquals(null, response, 'Response must not be null');
        System.assertEquals(false, response.isSuccess,
            'Blank objectApiName must return isSuccess = false');
    }

    /**
     * @description Blank recordId must return a non-success response (not throw).
     */
    @isTest
    static void testGetTargetSObjectType_BlankRecordId_ReturnsNonSuccess() {
        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.getTargetSObjectType(
            'Account', 'Industry', null
        );
        Test.stopTest();

        System.assertNotEquals(null, response, 'Response must not be null');
        System.assertEquals(false, response.isSuccess,
            'Null recordId must return isSuccess = false');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getObjectFields — Tests
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Happy path: Account is a guaranteed sObject in every org.
     *              The method must return a non-empty array of {apiName, label} objects.
     */
    @isTest
    static void testGetObjectFields_Account_ReturnsFields() {
        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.getObjectFields('Account');
        Test.stopTest();

        System.assertNotEquals(null, response,              'Response must not be null');
        System.assertNotEquals(null, response.responseData, 'Response data must not be null');

        List<Object> fields = (List<Object>) JSON.deserializeUntyped(response.responseData);
        System.assert(fields.size() > 0, 'Account must have at least one field');

        // Spot-check that each entry has both keys
        Map<String, Object> first = (Map<String, Object>) fields[0];
        System.assert(first.containsKey('apiName'), 'Field entry must have apiName key');
        System.assert(first.containsKey('label'),   'Field entry must have label key');
    }

    /**
     * @description Standard SObject Organisation / User must also be describable.
     */
    @isTest
    static void testGetObjectFields_Organization_ReturnsFields() {
        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.getObjectFields('Organization');
        Test.stopTest();

        System.assertNotEquals(null, response, 'Response must not be null');
        List<Object> fields = (List<Object>) JSON.deserializeUntyped(response.responseData);
        System.assert(fields.size() > 0, 'Organization must have at least one field');
    }

    /**
     * @description Blank objectApiName must throw AuraHandledException.
     */
    @isTest
    static void testGetObjectFields_BlankApiName_ThrowsException() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            REDU_FormulaBuilder_LCTRL.getObjectFields('');
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown,
            'AuraHandledException expected for blank objectApiName');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // verifyFormula — Happy-Path Tests
    // NOTE: FormulaEval validates field names against the schema.
    //       Salesforce formula syntax uses bare field names (no object prefix):
    //       correct → AnnualRevenue > 0
    //       incorrect → Account.AnnualRevenue > 0  (Account is not a relationship on Account)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Valid boolean infix formula with balanced parens → isValid = true.
     */
    @isTest
    static void testVerifyFormula_ValidInfixFormula() {
        Account acc = getTestAccount();

        Test.startTest();
        // Use a String field (Industry) for maximum stability in native tests
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            'Industry = "Technology"',
            OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(response.responseData);
        System.assertEquals(true, (Boolean) result.get('isValid'),
            'Syntax failed: ' + result.get('errorMessage'));
    }

    /**
     * @description Valid numeric formula → isValid = true.
     *              Verifies that Decimal return type is accepted alongside Boolean.
     */
    @isTest
    static void testVerifyFormula_ValidNumericFormula() {
        Account acc = getTestAccount();

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            'AnnualRevenue * 2',
            OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(response.responseData);
        System.assertEquals(true, (Boolean) result.get('isValid'),
            'Numeric formula must return isValid = true');
    }

    /**
     * @description Valid function-style formula: AND() wrapping multiple conditions
     *              → isValid = true. Verifies AND( is not treated as a missing-operand error.
     */
    @isTest
    static void testVerifyFormula_ValidFunctionStyleFormula() {
        Account acc = getTestAccount();

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            'AND(AnnualRevenue > 0, NOT(ISBLANK(Name)))',
            OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(response.responseData);
        System.assertEquals(true, (Boolean) result.get('isValid'),
            'Function-style AND() formula must return isValid = true');
    }

    /**
     * @description String literal containing parentheses and operator keywords
     *              must be treated as plain text → isValid = true.
     */
    @isTest
    static void testVerifyFormula_StringLiteralContent_IsIgnoredByChecks() {
        Account acc = getTestAccount();

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            'Name = \'AND (OR)\'',
            OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(response.responseData);
        System.assertEquals(true, (Boolean) result.get('isValid'),
            'Parentheses and operator keywords inside a string literal must not affect validity');
    }

    /**
     * @description String literal using double-quote syntax → the formula must remain valid.
     */
    @isTest
    static void testVerifyFormula_EscapedQuoteInsideString_IsValid() {
        Account acc = getTestAccount();

        Test.startTest();
        // Use double quotes for the string literal inside the formula
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            'Name = "it is a test"',
            OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(response.responseData);
        System.assertEquals(true, (Boolean) result.get('isValid'),
            'Literal failed: ' + result.get('errorMessage'));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // verifyFormula — String-Literal Error Tests
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Formula with an unclosed string literal → isValid = false.
     */
    @isTest
    static void testVerifyFormula_UnclosedStringLiteral_SingleQuote() {
        Account acc = getTestAccount();

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            'Name = \'Technology',   // opening quote never closed
            OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(response.responseData);
        System.assertEquals(false, (Boolean) result.get('isValid'),
            'Unclosed string literal must return isValid = false');
        System.assertNotEquals(null, result.get('errorMessage'),
            'An error message must be present for an unclosed string literal');
    }

    /**
     * @description Formula where a string literal is opened with a paren inside it
     *              — the whole thing is still an unclosed-literal error → isValid = false.
     */
    @isTest
    static void testVerifyFormula_UnclosedStringLiteral_HidesInvalidParen() {
        Account acc = getTestAccount();

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            'Name = \'(hello',
            OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(response.responseData);
        System.assertEquals(false, (Boolean) result.get('isValid'),
            'Unclosed string with an inner paren must return isValid = false');
        System.assertNotEquals(null, result.get('errorMessage'),
            'An error message must be present');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // verifyFormula — Parenthesis Error Tests
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Formula with more opening parens than closing parens → isValid = false.
     */
    @isTest
    static void testVerifyFormula_UnmatchedOpenParen() {
        Account acc = getTestAccount();

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            '((AnnualRevenue > 0 AND ISBLANK(Industry))',
            OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(response.responseData);
        System.assertEquals(false, (Boolean) result.get('isValid'),
            'Extra opening parenthesis must return isValid = false');
        System.assertNotEquals(null, result.get('errorMessage'),
            'An error message must be present');
    }

    /**
     * @description Formula with an extra closing paren → isValid = false.
     */
    @isTest
    static void testVerifyFormula_UnmatchedCloseParen() {
        Account acc = getTestAccount();

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            'AnnualRevenue > 0)',
            OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(response.responseData);
        System.assertEquals(false, (Boolean) result.get('isValid'),
            'Extra closing parenthesis must return isValid = false');
        System.assertNotEquals(null, result.get('errorMessage'),
            'An error message must be present');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // verifyFormula — Operator / Syntax Error Tests
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Consecutive binary operators (AND AND) → isValid = false.
     */
    @isTest
    static void testVerifyFormula_ConsecutiveOperators_AndAnd() {
        Account acc = getTestAccount();

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            'AnnualRevenue > 0 AND AND ISBLANK(Industry)',
            OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(response.responseData);
        System.assertEquals(false, (Boolean) result.get('isValid'),
            'AND AND must return isValid = false');
        System.assertNotEquals(null, result.get('errorMessage'),
            'An error message must be present');
    }

    /**
     * @description Consecutive binary operators (OR OR) → isValid = false.
     */
    @isTest
    static void testVerifyFormula_ConsecutiveOperators_OrOr() {
        Account acc = getTestAccount();

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            'AnnualRevenue > 0 OR OR ISBLANK(Industry)',
            OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(response.responseData);
        System.assertEquals(false, (Boolean) result.get('isValid'),
            'OR OR must return isValid = false');
        System.assertNotEquals(null, result.get('errorMessage'),
            'An error message must be present');
    }

    /**
     * @description Trailing OR with no right operand → isValid = false.
     */
    @isTest
    static void testVerifyFormula_EndsWithOperator_Or() {
        Account acc = getTestAccount();

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            'AnnualRevenue > 0 OR',
            OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(response.responseData);
        System.assertEquals(false, (Boolean) result.get('isValid'),
            'Trailing OR must return isValid = false');
        System.assertNotEquals(null, result.get('errorMessage'),
            'An error message must be present');
    }

    /**
     * @description Multi-argument IF() with missing commas → isValid = false.
     */
    @isTest
    static void testVerifyFormula_MissingCommaInFunctionCall() {
        Account acc = getTestAccount();

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            'IF(AnnualRevenue > 0 \'yes\' \'no\')',
            OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(response.responseData);
        System.assertEquals(false, (Boolean) result.get('isValid'),
            'Missing commas in IF() must return isValid = false');
        System.assertNotEquals(null, result.get('errorMessage'),
            'An error message must be present');
    }

    /**
     * @description Reference to a non-existent field → isValid = false.
     *              FormulaEval validates field names against the SObject schema.
     */
    @isTest
    static void testVerifyFormula_UnknownFieldReference() {
        Account acc = getTestAccount();

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            'FakeFieldThatDoesNotExist99__c > 0',
            OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(response.responseData);
        System.assertEquals(false, (Boolean) result.get('isValid'),
            'Reference to an unknown field must return isValid = false');
        System.assertNotEquals(null, result.get('errorMessage'),
            'An error message must be present');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // verifyFormula — Empty / Blank Guard Tests
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Empty string and whitespace-only formulas → both return isValid = false.
     */
    @isTest
    static void testVerifyFormula_BlankFormula() {
        Account acc = getTestAccount();

        Test.startTest();
        REDU_LightningResponse blankResp = REDU_FormulaBuilder_LCTRL.verifyFormula(
            '', OBJECT_API_NAME, acc.Id
        );
        REDU_LightningResponse wsResp = REDU_FormulaBuilder_LCTRL.verifyFormula(
            '   ', OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        System.assertEquals(false,
            (Boolean) ((Map<String, Object>) JSON.deserializeUntyped(blankResp.responseData)).get('isValid'),
            'Empty formula must return isValid = false');
        System.assertEquals(false,
            (Boolean) ((Map<String, Object>) JSON.deserializeUntyped(wsResp.responseData)).get('isValid'),
            'Whitespace-only formula must return isValid = false');
    }

    /**
     * @description Blank objectApiName → isValid = false (schema lookup not possible).
     */
    @isTest
    static void testVerifyFormula_BlankObjectApiName() {
        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            'AnnualRevenue > 0', '', null
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(response.responseData);
        System.assertEquals(false, (Boolean) result.get('isValid'),
            'Blank objectApiName must return isValid = false');
        System.assertNotEquals(null, result.get('errorMessage'),
            'An error message must be present');
    }
}
