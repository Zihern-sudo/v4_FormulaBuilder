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
    // Uses a properly closed string literal so it is syntactically valid.
    private static final String INITIAL_FORMULA =
        'Account.Industry = \'Technology\' AND Account.AnnualRevenue > 0';

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

        System.assertNotEquals(null, response,      'Response must not be null');
        System.assertNotEquals(null, response.data, 'Response data must not be null');
        System.assertEquals(INITIAL_FORMULA, (String) response.data,
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

        System.assertEquals('', (String) response.data,
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
        System.assertEquals(true, (Boolean) response.data,
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

        System.assertNotEquals(null, response,      'Response must not be null');
        System.assertNotEquals(null, response.data, 'Response data must not be null');

        List<Object> mdtNames = (List<Object>) response.data;
        System.assert(mdtNames.size() > 0,
            'At least one Custom Metadata Type must exist in the org');

        for (Object nameObj : mdtNames) {
            String name = (String) nameObj;
            System.assert(name.toLowerCase().endsWith('__mdt'),
                'All returned names must end with __mdt but got: ' + name);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // verifyFormula — Happy-Path Tests
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Valid infix formula with correctly closed string literals,
     *              balanced parens, and proper operators → isValid = true.
     */
    @isTest
    static void testVerifyFormula_ValidInfixFormula() {
        Account acc     = getTestAccount();
        String  formula = '(Account.Industry = \'Technology\') AND (Account.AnnualRevenue > 1000000)';

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            formula, OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) response.data;
        System.assertEquals(true, (Boolean) result.get('isValid'),
            'Valid infix formula must return isValid = true');
        System.assertEquals(null, result.get('errorMessage'),
            'Valid formula must return no errorMessage');
    }

    /**
     * @description Valid function-style formula: AND() wrapping multiple conditions
     *              → isValid = true. Verifies AND( is not treated as a binary operator.
     */
    @isTest
    static void testVerifyFormula_ValidFunctionStyleFormula() {
        Account acc     = getTestAccount();
        String  formula =
            'AND(\n' +
            '  reduvivy__Default_Campus__c.Name = \'Sydney\',\n' +
            '  NOT(ISBLANK(reduvivy__Contact__c))\n' +
            ')';

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            formula, OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) response.data;
        System.assertEquals(true, (Boolean) result.get('isValid'),
            'Function-style AND() formula must return isValid = true');
    }

    /**
     * @description String literal containing parentheses and operator keywords
     *              — none of those characters should affect parenthesis depth or
     *              trigger operator checks → isValid = true.
     */
    @isTest
    static void testVerifyFormula_StringLiteralContent_IsIgnoredByChecks() {
        Account acc     = getTestAccount();
        String  formula = 'Account.Name = \'AND (OR)\'';

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            formula, OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) response.data;
        System.assertEquals(true, (Boolean) result.get('isValid'),
            'Parentheses and operator keywords inside a string literal must not affect validity');
    }

    /**
     * @description String literal containing an escaped single quote ('')
     *              → the formula must remain valid (the '' does not close the string).
     */
    @isTest
    static void testVerifyFormula_EscapedQuoteInsideString_IsValid() {
        Account acc     = getTestAccount();
        String  formula = 'Account.Name = \'it\'\'s a test\'';

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            formula, OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) response.data;
        System.assertEquals(true, (Boolean) result.get('isValid'),
            'Escaped single quote (\'\') inside a string must not be treated as closing the literal');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // verifyFormula — String-Literal Error Tests (Check A)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Formula with an unclosed string literal → isValid = false
     *              and errorMessage must reference the string literal problem.
     */
    @isTest
    static void testVerifyFormula_UnclosedStringLiteral_SingleQuote() {
        Account acc     = getTestAccount();
        String  formula = 'Account.Name = \'Technology'; // opening quote never closed

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            formula, OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) response.data;
        System.assertEquals(false, (Boolean) result.get('isValid'),
            'Unclosed string literal must return isValid = false');

        String errMsg = (String) result.get('errorMessage');
        System.assertNotEquals(null, errMsg,
            'An error message must be present for an unclosed string literal');
        System.assert(
            errMsg.containsIgnoreCase('single quote') || errMsg.containsIgnoreCase('string literal'),
            'Error message must reference the string literal problem; got: ' + errMsg
        );
    }

    /**
     * @description Formula where a string literal is opened and the remaining content
     *              also has a paren — the paren is inside the unclosed string and must
     *              NOT register as a paren error (string-literal check fires first).
     */
    @isTest
    static void testVerifyFormula_UnclosedStringLiteral_HidesInvalidParen() {
        Account acc     = getTestAccount();
        String  formula = 'Account.Name = \'(hello';

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            formula, OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) response.data;
        System.assertEquals(false, (Boolean) result.get('isValid'),
            'Unclosed string with an inner paren must return isValid = false');

        String errMsg = (String) result.get('errorMessage');
        System.assert(
            errMsg.containsIgnoreCase('single quote') || errMsg.containsIgnoreCase('string literal'),
            'Error must report the unclosed string literal, not a parenthesis problem; got: ' + errMsg
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // verifyFormula — Parenthesis Error Tests (Checks A / B)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Formula with more opening parens than closing parens → isValid = false.
     */
    @isTest
    static void testVerifyFormula_UnmatchedOpenParen() {
        Account acc     = getTestAccount();
        String  formula = '((Account.Industry = \'Technology\' AND Account.AnnualRevenue > 0)';

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            formula, OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) response.data;
        System.assertEquals(false, (Boolean) result.get('isValid'),
            'Extra opening parenthesis must return isValid = false');
        System.assertNotEquals(null, result.get('errorMessage'),
            'An error message must be present');
    }

    /**
     * @description Formula with an extra closing paren → isValid = false with
     *              a character-position reference in the error message.
     */
    @isTest
    static void testVerifyFormula_UnmatchedCloseParen() {
        Account acc     = getTestAccount();
        String  formula = 'Account.Industry = \'Technology\') AND Account.AnnualRevenue > 0';

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            formula, OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) response.data;
        System.assertEquals(false, (Boolean) result.get('isValid'),
            'Extra closing parenthesis must return isValid = false');
        System.assertNotEquals(null, result.get('errorMessage'),
            'An error message must be present');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // verifyFormula — Operator Error Tests (Checks C–G)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Consecutive binary operators (AND AND) → isValid = false.
     */
    @isTest
    static void testVerifyFormula_ConsecutiveOperators_AndAnd() {
        Account acc     = getTestAccount();
        String  formula = 'Account.Industry = \'Technology\' AND AND Account.AnnualRevenue > 0';

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            formula, OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) response.data;
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
        Account acc     = getTestAccount();
        String  formula = 'Account.Industry = \'Technology\' OR OR Account.AnnualRevenue > 0';

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            formula, OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) response.data;
        System.assertEquals(false, (Boolean) result.get('isValid'),
            'OR OR must return isValid = false');
    }

    /**
     * @description Formula starting with a binary operator (AND) → isValid = false.
     */
    @isTest
    static void testVerifyFormula_StartsWithBinaryOperator() {
        Account acc     = getTestAccount();
        String  formula = 'AND Account.Industry = \'Technology\'';

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            formula, OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) response.data;
        System.assertEquals(false, (Boolean) result.get('isValid'),
            'Leading AND must return isValid = false');
    }

    /**
     * @description Formula ending with OR → isValid = false.
     */
    @isTest
    static void testVerifyFormula_EndsWithOperator_Or() {
        Account acc     = getTestAccount();
        String  formula = 'Account.Industry = \'Technology\' OR';

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            formula, OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) response.data;
        System.assertEquals(false, (Boolean) result.get('isValid'),
            'Trailing OR must return isValid = false');
    }

    /**
     * @description Formula ending with NOT → isValid = false.
     */
    @isTest
    static void testVerifyFormula_EndsWithOperator_Not() {
        Account acc     = getTestAccount();
        String  formula = 'Account.Industry = \'Technology\' NOT';

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            formula, OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) response.data;
        System.assertEquals(false, (Boolean) result.get('isValid'),
            'Trailing NOT must return isValid = false');
    }

    /**
     * @description Multi-argument function call with a missing comma between
     *              arguments → isValid = false.
     */
    @isTest
    static void testVerifyFormula_MissingCommaInFunctionCall() {
        Account acc     = getTestAccount();
        String  formula = 'IF(Account.AnnualRevenue > 0 \'yes\' \'no\')';

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            formula, OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) response.data;
        System.assertEquals(false, (Boolean) result.get('isValid'),
            'Missing comma in IF() must return isValid = false');
        System.assertNotEquals(null, result.get('errorMessage'),
            'An error message must be present');
    }

    /**
     * @description Double-equals comparison operator (==) → isValid = false.
     */
    @isTest
    static void testVerifyFormula_InvalidOperator_DoubleEquals() {
        Account acc     = getTestAccount();
        String  formula = 'Account.Industry == \'Technology\'';

        Test.startTest();
        REDU_LightningResponse response = REDU_FormulaBuilder_LCTRL.verifyFormula(
            formula, OBJECT_API_NAME, acc.Id
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) response.data;
        System.assertEquals(false, (Boolean) result.get('isValid'),
            'Double-equals operator must return isValid = false');
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
            (Boolean) ((Map<String, Object>) blankResp.data).get('isValid'),
            'Empty formula must return isValid = false');
        System.assertEquals(false,
            (Boolean) ((Map<String, Object>) wsResp.data).get('isValid'),
            'Whitespace-only formula must return isValid = false');
    }
}
