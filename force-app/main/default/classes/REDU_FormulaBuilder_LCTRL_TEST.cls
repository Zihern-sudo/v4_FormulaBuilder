/**
 * @Author      WDCi ()
 * @Date        April 2026
 * @group       Formula Builder
 * @Description Test class for REDU_FormulaBuilder_LCTRL. Covers getFieldValue,
 *              updateFieldValue, getCustomMetadataTypes, and verifyFormula,
 *              including happy paths and negative/error scenarios.
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
    private static final String FORMULA_VALUE   = 'Account.Industry = \'Technology\' AND Account.AnnualRevenue > 0';

    // ─────────────────────────────────────────────────────────────────────────
    // Test Setup
    // ─────────────────────────────────────────────────────────────────────────

    @TestSetup
    static void makeData() {
        Account acc = new Account(
            Name        = 'Formula Builder Test Account',
            Description = FORMULA_VALUE,
            Industry    = 'Technology'
        );
        insert acc;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getFieldValue Tests
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Happy path: verifies that a valid field value is returned
     *              for an existing record
     */
    @isTest
    static void testGetFieldValue_Success() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Formula Builder Test Account' LIMIT 1];

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.getFieldValue(
            OBJECT_API_NAME,
            FIELD_API_NAME,
            acc.Id
        );
        Test.stopTest();

        System.assertNotEquals(null, response,       'Response should not be null');
        System.assertNotEquals(null, response.data,  'Response data should not be null');
        System.assertEquals(
            FORMULA_VALUE,
            (String) response.data,
            'Returned field value should match the inserted Description'
        );
    }

    /**
     * @description Negative path: verifies that a blank objectApiName throws
     *              an AuraHandledException
     */
    @isTest
    static void testGetFieldValue_BlankObjectApiName_ThrowsException() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Formula Builder Test Account' LIMIT 1];

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            REDU_FormulaBuilder_LCTRL.getFieldValue('', FIELD_API_NAME, acc.Id);
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'An AuraHandledException should be thrown for blank objectApiName');
    }

    /**
     * @description Negative path: verifies that a null recordId throws
     *              an AuraHandledException
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

        System.assert(exceptionThrown, 'An AuraHandledException should be thrown for null recordId');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // updateFieldValue Tests
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Happy path: verifies that updateFieldValue persists the new
     *              formula string to the target field
     */
    @isTest
    static void testUpdateFieldValue_Success() {
        Account acc            = [SELECT Id FROM Account WHERE Name = 'Formula Builder Test Account' LIMIT 1];
        String  newFormula     = 'Account.Industry = \'Finance\' OR Account.AnnualRevenue >= 500000';

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.updateFieldValue(
            OBJECT_API_NAME,
            FIELD_API_NAME,
            acc.Id,
            newFormula
        );
        Test.stopTest();

        System.assertNotEquals(null, response, 'Response should not be null');
        System.assertEquals(true, (Boolean) response.data, 'Response data should be true on success');

        Account updated = [SELECT Description FROM Account WHERE Id = :acc.Id LIMIT 1];
        System.assertEquals(newFormula, updated.Description, 'Description field should reflect the updated formula');
    }

    /**
     * @description Verifies that updateFieldValue clears a formula when an
     *              empty string is passed (null-out scenario)
     */
    @isTest
    static void testUpdateFieldValue_ClearFormula() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Formula Builder Test Account' LIMIT 1];

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.updateFieldValue(
            OBJECT_API_NAME,
            FIELD_API_NAME,
            acc.Id,
            ''
        );
        Test.stopTest();

        System.assertNotEquals(null, response, 'Response should not be null');

        Account updated = [SELECT Description FROM Account WHERE Id = :acc.Id LIMIT 1];
        System.assertEquals('', updated.Description == null ? '' : updated.Description,
            'Description should be empty/null after clearing formula');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getCustomMetadataTypes Tests
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Happy path: verifies that getCustomMetadataTypes returns a
     *              non-null list (at least one __mdt type is expected in any org)
     */
    @isTest
    static void testGetCustomMetadataTypes_Success() {
        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.getCustomMetadataTypes();
        Test.stopTest();

        System.assertNotEquals(null, response,      'Response should not be null');
        System.assertNotEquals(null, response.data, 'Response data list should not be null');

        List<Object> mdtNames = (List<Object>) response.data;
        System.assert(mdtNames.size() > 0, 'At least one Custom Metadata Type should exist in the org');

        // Verify all returned names end with __mdt (case-insensitive)
        for (Object nameObj : mdtNames) {
            String name = (String) nameObj;
            System.assert(
                name.toLowerCase().endsWith('__mdt'),
                'All returned type names should end with __mdt but got: ' + name
            );
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // verifyFormula Tests
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Happy path: verifies that a syntactically correct formula
     *              returns isValid = true with no errorMessage
     */
    @isTest
    static void testVerifyFormula_ValidSyntax() {
        Account acc     = [SELECT Id FROM Account WHERE Name = 'Formula Builder Test Account' LIMIT 1];
        String  formula = '(Account.Industry = \'Technology\') AND (Account.AnnualRevenue > 1000000)';

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            formula,
            OBJECT_API_NAME,
            acc.Id
        );
        Test.stopTest();

        System.assertNotEquals(null, response, 'Response should not be null');
        Map<String, Object> result = (Map<String, Object>) response.data;
        System.assertEquals(true, (Boolean) result.get('isValid'),
            'A valid formula should return isValid = true');
        System.assertEquals(null, result.get('errorMessage'),
            'A valid formula should return no errorMessage');
    }

    /**
     * @description Verifies that a formula with unmatched opening parentheses
     *              returns isValid = false with a descriptive errorMessage
     */
    @isTest
    static void testVerifyFormula_UnmatchedOpenParen() {
        Account acc     = [SELECT Id FROM Account WHERE Name = 'Formula Builder Test Account' LIMIT 1];
        String  formula = '((Account.Industry = \'Technology\' AND Account.AnnualRevenue > 0)';

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            formula,
            OBJECT_API_NAME,
            acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) response.data;
        System.assertEquals(false, (Boolean) result.get('isValid'),
            'An unmatched open parenthesis should return isValid = false');
        System.assertNotEquals(null, result.get('errorMessage'),
            'An error message should be provided for unmatched parenthesis');
    }

    /**
     * @description Verifies that a formula with unmatched closing parentheses
     *              returns isValid = false with a descriptive errorMessage
     */
    @isTest
    static void testVerifyFormula_UnmatchedCloseParen() {
        Account acc     = [SELECT Id FROM Account WHERE Name = 'Formula Builder Test Account' LIMIT 1];
        String  formula = 'Account.Industry = \'Technology\') AND Account.AnnualRevenue > 0';

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            formula,
            OBJECT_API_NAME,
            acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) response.data;
        System.assertEquals(false, (Boolean) result.get('isValid'),
            'An unmatched closing parenthesis should return isValid = false');
    }

    /**
     * @description Negative path: verifies that a malformed formula with
     *              consecutive operators returns isValid = false with an errorMessage
     */
    @isTest
    static void testVerifyFormula_InvalidSyntax_ConsecutiveOperators() {
        Account acc     = [SELECT Id FROM Account WHERE Name = 'Formula Builder Test Account' LIMIT 1];
        String  formula = 'Account.Industry = \'Technology\' AND AND Account.AnnualRevenue > 0';

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            formula,
            OBJECT_API_NAME,
            acc.Id
        );
        Test.stopTest();

        System.assertNotEquals(null, response, 'Response should not be null');
        Map<String, Object> result = (Map<String, Object>) response.data;
        System.assertEquals(false, (Boolean) result.get('isValid'),
            'Consecutive operators should return isValid = false');
        System.assertNotEquals(null, result.get('errorMessage'),
            'An error message should be present for consecutive operators');
    }

    /**
     * @description Verifies that a formula starting with a binary operator
     *              returns isValid = false
     */
    @isTest
    static void testVerifyFormula_StartsWithBinaryOperator() {
        Account acc     = [SELECT Id FROM Account WHERE Name = 'Formula Builder Test Account' LIMIT 1];
        String  formula = 'AND Account.Industry = \'Technology\'';

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            formula,
            OBJECT_API_NAME,
            acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) response.data;
        System.assertEquals(false, (Boolean) result.get('isValid'),
            'Formula starting with AND should return isValid = false');
    }

    /**
     * @description Verifies that a formula ending with an operator
     *              returns isValid = false
     */
    @isTest
    static void testVerifyFormula_EndsWithOperator() {
        Account acc     = [SELECT Id FROM Account WHERE Name = 'Formula Builder Test Account' LIMIT 1];
        String  formula = 'Account.Industry = \'Technology\' OR';

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            formula,
            OBJECT_API_NAME,
            acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) response.data;
        System.assertEquals(false, (Boolean) result.get('isValid'),
            'Formula ending with OR should return isValid = false');
    }

    /**
     * @description Verifies that a blank or null formula returns isValid = false
     */
    @isTest
    static void testVerifyFormula_BlankFormula() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Formula Builder Test Account' LIMIT 1];

        Test.startTest();
        REDU_LightningResponse blankResponse = REDU_FormulaBuilder_LCTRL.verifyFormula(
            '',
            OBJECT_API_NAME,
            acc.Id
        );
        REDU_LightningResponse whitespaceResponse = REDU_FormulaBuilder_LCTRL.verifyFormula(
            '   ',
            OBJECT_API_NAME,
            acc.Id
        );
        Test.stopTest();

        Map<String, Object> blankResult = (Map<String, Object>) blankResponse.data;
        System.assertEquals(false, (Boolean) blankResult.get('isValid'),
            'Blank formula should return isValid = false');

        Map<String, Object> wsResult = (Map<String, Object>) whitespaceResponse.data;
        System.assertEquals(false, (Boolean) wsResult.get('isValid'),
            'Whitespace-only formula should return isValid = false');
    }

    /**
     * @description Verifies that a formula with double-equals invalid operator
     *              returns isValid = false
     */
    @isTest
    static void testVerifyFormula_InvalidOperator_DoubleEquals() {
        Account acc     = [SELECT Id FROM Account WHERE Name = 'Formula Builder Test Account' LIMIT 1];
        String  formula = 'Account.Industry == \'Technology\'';

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            formula,
            OBJECT_API_NAME,
            acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) response.data;
        System.assertEquals(false, (Boolean) result.get('isValid'),
            'Double-equals operator should return isValid = false');
    }
}
