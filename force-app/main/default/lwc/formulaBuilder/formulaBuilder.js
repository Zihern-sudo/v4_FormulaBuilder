/**
 * @Author      WDCi (Zihern)
 * @Date        April 2026
 * @group       Formula Builder
 * @Description JavaScript controller for the formulaBuilder LWC.
 *              Provides a full formula-editing experience: view mode shows the
 *              current formula value with an Edit button; edit mode exposes four
 *              comboboxes (System Variables, Fields, Functions, Operators) that
 *              insert tokens at the current cursor position, a live-editable
 *              formula textarea, and an Update / Cancel / Verify Formula action pair.
 *
 *              Verification is opt-in via the Verify Formula modal — the Update
 *              button is always available (not gated on verification) but the editor
 *              shows a hint encouraging the user to verify before saving.  The modal
 *              retains the record Id and last result between opens so the user can
 *              correct a formula and click Verify without re-entering data.
 *
 *              All Apex calls are imperative. getObjectInfo wire populates the
 *              Fields combobox reactively from the configured object.
 * @changehistory
 * ISS-002768 2026-04-03 - Initial development of Formula Builder LWC JavaScript controller
 * ISS-002768 2026-04-06 - Verify Formula modal; verification opt-in; explicit Verify button
 */
import { LightningElement, api, track, wire } from 'lwc';
import { getObjectInfo }                       from 'lightning/uiObjectInfoApi';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';

import { ShowToastEvent }    from 'lightning/platformShowToastEvent';
import { getErrorMessage, logInfo } from 'c/loggingUtil';
import { initCacheIdx }                              from 'c/lwcUtil';

import apexGetFieldValue        from '@salesforce/apex/REDU_FormulaBuilder_LCTRL.getFieldValue';
import apexUpdateFieldValue     from '@salesforce/apex/REDU_FormulaBuilder_LCTRL.updateFieldValue';
import apexVerifyFormula        from '@salesforce/apex/REDU_FormulaBuilder_LCTRL.verifyFormula';
import apexGetTargetSObjectType from '@salesforce/apex/REDU_FormulaBuilder_LCTRL.getTargetSObjectType';
import apexGetObjectFields      from '@salesforce/apex/REDU_FormulaBuilder_LCTRL.getObjectFields';

// ─── Component identifier for log statements ──────────────────────────────────
const COMPONENT = 'formulaBuilder';

// ─── Standard Salesforce formula global variable names ────────────────────────
// Permission and CustomMetadata are intentionally excluded.
const SYSTEM_VARIABLE_SEEDS = [
    'Organization', 'Profile', 'Setup', 'System', 'User', 'UserRole'
];

// ─── Full Salesforce formula function library (ISS-002768) ────────────────────
const FUNCTION_NAMES = [
    'ABS',          'ADDMONTHS',     'AND',           'BEGINS',        'BLANKVALUE',
    'BR',           'CASE',          'CASESAFEID',    'CEILING',       'CONTAINS',
    'CURRENCYRATE', 'DATE',          'DATEVALUE',     'DATETIMEVALUE', 'DAY',
    'DISTANCE',     'EXP',           'FIND',          'FLOOR',         'GEOLOCATION',
    'GETRECORDIDS', 'GETSESSIONID',  'HOUR',          'HTMLENCODE',    'HYPERLINK',
    'IF',           'IMAGE',         'IMAGEPROXYURL', 'INCLUDE',       'INCLUDES',
    'ISBLANK',      'ISCHANGED',     'ISCLONE',       'ISNEW',         'ISNULL',
    'ISNUMBER',     'ISPICKVAL',     'JSENCODE',      'JSINHTMLENCODE','JUNCTIONIDLIST',
    'LEFT',         'LEN',           'LINKTO',        'LN',            'LOG',
    'LOWER',        'LPAD',          'MAX',           'MCEILING',      'MFLOOR',
    'MID',          'MILLISECOND',   'MIN',           'MINUTE',        'MOD',
    'MONTH',        'NOT',           'NOW',           'NULLVALUE',     'OR',
    'PARENTGROUPVAL','PREDICT',      'PREVGROUPVAL',  'REGEX',         'REQUIRESCRIPT',
    'REVERSE',      'RIGHT',         'ROUND',         'RPAD',          'SECOND',
    'SQRT',         'SUBSTITUTE',    'TEXT',          'TIMENOW',       'TIMEVALUE',
    'TODAY',        'TRIM',          'UPPER',         'URLENCODE',     'URLFOR',
    'VALUE',        'VLOOKUP',       'WEEKDAY',       'YEAR'
];

// ─── Full operator set (ISS-002768) ───────────────────────────────────────────
// label = display text in combobox; value = token inserted into the formula.
const OPERATOR_DEFINITIONS = [
    { label: '+ (Add)',                     value: ' + '  },
    { label: '- (Subtract)',                value: ' - '  },
    { label: '* (Multiply)',                value: ' * '  },
    { label: '/ (Divide)',                  value: ' / '  },
    { label: '^ (Exponentiation)',          value: ' ^ '  },
    { label: '() (Parenthesis)',            value: '()'   },
    { label: '= (Equal)',                   value: ' = '  },
    { label: '== (Equal)',                  value: ' == ' },
    { label: '<> (Not Equal)',              value: ' <> ' },
    { label: '!= (Not Equal)',              value: ' != ' },
    { label: '< (Less Than)',               value: ' < '  },
    { label: '> (Greater Than)',            value: ' > '  },
    { label: '<= (Less Than or Equal)',     value: ' <= ' },
    { label: '>= (Greater Than or Equal)',  value: ' >= ' },
    { label: '&& (AND)',                    value: ' && ' },
    { label: '|| (OR)',                     value: ' || ' },
    { label: '& (Concatenate)',             value: ' & '  }
];

/** Blank sentinel option prepended to every combobox */
const BLANK_OPTION = { label: 'Select an Option', value: '' };

export default class FormulaBuilder extends LightningElement {

    // ─── Public API ───────────────────────────────────────────────────────────

    /**
     * @description Salesforce record Id of the record whose field is being edited.
     *              Supplied automatically by the Lightning record page context.
     */
    @api recordId;

    /**
     * @description API name of the Salesforce object that owns the formula field
     *              (e.g. Study_Requirement_Set__c).
     */
    @api targetObjectApiName;

    /**
     * @description API name of the field that stores the formula string
     *              (e.g. Criteria__c).
     */
    @api targetFieldApiName;

    /**
     * @description When false (default) the Edit button is hidden and the
     *              component renders in read-only view mode permanently.
     */
    @api allowEdit = false;

    /**
     * @description When true, debug log statements are emitted via logInfo.
     *              Set to false in production to suppress console output.
     */
    @api enableDebugMode = false;

    // ─── Tracked State ────────────────────────────────────────────────────────

    /** True while the formula editor (edit mode) is visible */
    @track isEditMode = false;

    /** Live formula text — bound to the textarea value */
    @track currentFormulaValue = '';

    /** Snapshot taken on load / after a successful save — used by Cancel */
    @track originalFormulaValue = '';

    /** Human-readable label of targetFieldApiName, resolved via getObjectInfo */
    @track fieldLabel = '';

    /** Options for the System Variables combobox (seeds + org Custom MDTs) */
    @track systemVariableOptions = [];

    /** Options for the Fields combobox, populated from getObjectInfo */
    @track fieldOptions = [];

    /** Options for the Functions combobox (static full list) */
    @track functionOptions = [];

    /** Options for the Operators combobox (static full list) */
    @track operatorOptions = [];

    /** Controls visibility of the Verify Formula modal */
    @track isVerifyModalOpen = false;

    /** Result object from the last verifyFormula call: { isValid, message } */
    @track verifyModalResult = null;

    /** Drives the loading spinner; set via toggleSpinner(±1) */
    @track isLoading = false;

    // ─── Per-combobox selection state (reset to '' after each insertion) ──────

    @track _selectedSystemVariable = '';
    @track _selectedField          = '';
    @track _selectedFunction       = '';
    @track _selectedOperator       = '';

    /** Record Id typed into the inline verify input */
    @track _verifyRecordId = '';

    // ─── Private State ────────────────────────────────────────────────────────

    /** Depth counter for nested async calls — spinner shows when > 0 */
    _spinnerCount = 0;

    /** Token returned by registerRefreshHandler */
    _refreshHandler;

    /**
     * @description Set to true at the end of connectedCallback once all
     *              synchronous setup is complete.  Gates the main template
     *              via the isInitSuccess getter.
     */
    _initComplete = false;

    /**
     * @description Pending cursor position to restore after a combobox insertion
     *              causes the textarea to re-render with a new value.
     *              Set by _insertAtCursor; consumed and cleared in renderedCallback.
     */
    _pendingCursorPos = undefined;

    /**
     * @description The base SObject that physically stores the formula field
     *              (i.e. the object used in getFieldValue / updateFieldValue SOQL).
     *              Parsed from targetObjectApiName — always the plain API name
     *              with no '{}' suffix.  Drives the getObjectInfo wire adapter so
     *              fieldLabel resolves correctly even when a dynamic target is used.
     */
    _storageObjectApiName = '';

    /**
     * @description The SObject whose fields populate the System Variables first option
     *              and the Fields combobox.  Equals _storageObjectApiName for plain-format
     *              inputs; resolved via Apex for dynamic '{relationship.field}' inputs.
     */
    _targetSObjectApiName = '';

    /** Cache-buster incremented by initCacheIdx to signal data reload */
    cacheIdx = 0;

    // ─── Wire: Object Info ────────────────────────────────────────────────────

    /**
     * @description Reactively fetches field metadata whenever targetObjectApiName
     *              changes.  Populates fieldOptions and resolves fieldLabel for
     *              the configured targetFieldApiName.
     * @param {Object} wireResult Standard LWC wire result { data, error }
     */
    // Wired to _storageObjectApiName (the plain base object API name without any '{}' suffix).
    // Resolves fieldLabel for view-mode display.  Cannot wire to targetObjectApiName directly
    // because that @api prop may contain the dynamic '{relationship.field}' format which is
    // not a valid SObject name and would cause the wire to return an error.
    @wire(getObjectInfo, { objectApiName: '$_storageObjectApiName' })
    wiredObjectInfo({ error, data }) {
        if (data) {
            this.consoleLog('wiredObjectInfo — received data', { objectApiName: this._storageObjectApiName });
            if (this.targetFieldApiName && data.fields[this.targetFieldApiName]) {
                this.fieldLabel = data.fields[this.targetFieldApiName].label;
            }
        } else if (error) {
            this.consoleLog('wiredObjectInfo — error', error);
        }
    }

    // ─── Lifecycle Hooks ──────────────────────────────────────────────────────

    /**
     * @description Initialises static combobox lists, loads Custom Metadata
     *              Types imperatively, and — when the component is fully
     *              configured — loads the current formula field value.
     */
    connectedCallback() {
        this._refreshHandler = registerRefreshHandler(
            this,
            this.handleRefresh.bind(this)
        );

        // Initialise static option lists first (synchronous, no spinner needed)
        this._initFunctionOptions();
        this._initOperatorOptions();

        // Parse targetObjectApiName — supports both plain and dynamic '{rel.field}' formats.
        // _storageObjectApiName is always set here (plain API name, no '{}') so the
        // getObjectInfo wire adapter fires immediately and resolves fieldLabel.
        const { storageObject, isDynamic, fieldPath } = this._parseTargetConfig();
        this._storageObjectApiName = storageObject;

        if (isDynamic) {
            // Dynamic: query the record to resolve the actual SObject for the Fields combobox.
            this._loadDynamicTargetSObject(storageObject, fieldPath);
        } else {
            // Plain: use storageObject directly for both storage and formula-target roles.
            this._targetSObjectApiName = storageObject;
            this._buildSystemVariableOptions(storageObject);
            if (storageObject) { this._loadFieldsForSystemVariable(storageObject, true); }
        }

        // Async: load the current formula value when both object and field are set
        if (this.isConfigured) {
            this._loadFieldValue();
        }

        this.consoleLog('connectedCallback', {
            recordId            : this.recordId,
            targetObjectApiName : this.targetObjectApiName,
            targetFieldApiName  : this.targetFieldApiName,
            allowEdit           : this.allowEdit,
            enableDebugMode     : this.enableDebugMode
        });

        // Mark synchronous init complete — gates the isInitSuccess getter
        this._initComplete = true;
    }

    /**
     * @description Unregisters the refresh handler to prevent memory leaks.
     */
    disconnectedCallback() {
        unregisterRefreshHandler(this._refreshHandler);
    }

    /**
     * @description After each reactive re-render triggered by a combobox
     *              insertion, restores the cursor to the position immediately
     *              after the inserted token.
     *              Only operates on native <textarea> elements — lightning-textarea
     *              wraps its inner element in shadow DOM which is inaccessible,
     *              so cursor restoration is a no-op for that component.
     */
    renderedCallback() {
        if (this._pendingCursorPos !== undefined) {
            const el = this.template.querySelector('[data-id="formulaTextarea"]');
            // selectionStart is a number only on native <textarea> / <input> elements
            if (el && typeof el.selectionStart === 'number') {
                el.focus();
                el.setSelectionRange(this._pendingCursorPos, this._pendingCursorPos);
            }
            this._pendingCursorPos = undefined;
        }
    }

    // ─── Private Initialisation Helpers ──────────────────────────────────────

    /**
     * @description Builds functionOptions from the static FUNCTION_NAMES list.
     *              Each function is inserted with an opening parenthesis so the
     *              user can immediately start typing arguments.
     */
    _initFunctionOptions() {
        this.functionOptions = [
            BLANK_OPTION,
            ...FUNCTION_NAMES.map(fn => ({ label: fn, value: `${fn}(` }))
        ];
    }

    /**
     * @description Builds operatorOptions from the static OPERATOR_DEFINITIONS list.
     */
    _initOperatorOptions() {
        this.operatorOptions = [
            BLANK_OPTION,
            ...OPERATOR_DEFINITIONS.map(op => ({ label: op.label, value: op.value }))
        ];
    }

    /**
     * @description Parses the targetObjectApiName @api property which supports
     *              two formats set in the Lightning App Builder:
     *
     *                1. Plain:   'reduivy__Study_Scoring_Criteria__c'
     *                   → storageObject = 'reduivy__Study_Scoring_Criteria__c'
     *                   → isDynamic     = false
     *
     *                2. Dynamic: 'reduivy__Study_Scoring_Criteria__c
     *                             {reduivy__Study_Scoring_Config__r.reduivy__SObjectType__c}'
     *                   → storageObject = 'reduivy__Study_Scoring_Criteria__c'
     *                   → isDynamic     = true
     *                   → fieldPath     = 'reduivy__Study_Scoring_Config__r.reduivy__SObjectType__c'
     *
     *              The storage object is always the object that owns the formula field
     *              (used for getFieldValue / updateFieldValue).
     *              The fieldPath, when present, is resolved via Apex to obtain the
     *              actual SObject whose fields appear in the Fields combobox.
     *
     * @return {{ storageObject: string, isDynamic: boolean, fieldPath: string|null }}
     */
    _parseTargetConfig() {
        const raw = (this.targetObjectApiName || '').trim();
        // Remove any whitespace between the object name and the '{' before matching
        const normalised = raw.replace(/\s+/g, '');
        const match      = normalised.match(/^([^{]+)\{([^}]+)\}$/);
        if (match) {
            return { storageObject: match[1], isDynamic: true,  fieldPath: match[2] };
        }
        return { storageObject: raw,       isDynamic: false, fieldPath: null };
    }

    /**
     * @description Calls getTargetSObjectType() to resolve the actual SObject
     *              whose fields the formula references when the dynamic
     *              'BaseObject{relationship.field}' format is used.
     *              Falls back to storageObject on error or missing recordId.
     * @param {string} storageObject  Base object API name (without '{}')
     * @param {string} fieldPath      Cross-object field path inside the '{}'
     */
    _loadDynamicTargetSObject(storageObject, fieldPath) {
        if (!this.recordId) {
            // No record context — fall back to using the storage object itself
            this._targetSObjectApiName = storageObject;
            this._buildSystemVariableOptions(storageObject);
            if (storageObject) { this._loadFieldsForSystemVariable(storageObject, true); }
            return;
        }

        this.toggleSpinner(1);

        apexGetTargetSObjectType({
            objectApiName : storageObject,
            fieldPath     : fieldPath,
            recordId      : this.recordId
        })
        .then(response => {
            const resolved = response.responseData ? JSON.parse(response.responseData) : null;
            this._targetSObjectApiName = resolved || storageObject;
            this._buildSystemVariableOptions(this._targetSObjectApiName);
            this._loadFieldsForSystemVariable(this._targetSObjectApiName, true);
            this.consoleLog('_loadDynamicTargetSObject — resolved', {
                storageObject,
                fieldPath,
                resolved : this._targetSObjectApiName
            });
        })
        .catch(error => {
            this.consoleLog('_loadDynamicTargetSObject — error, falling back to storage object', error);
            this._targetSObjectApiName = storageObject;
            this._buildSystemVariableOptions(storageObject);
            if (storageObject) { this._loadFieldsForSystemVariable(storageObject, true); }
        })
        .finally(() => this.toggleSpinner(-1));
    }

    /**
     * @description Builds the System Variables combobox options.
     *              Order: [Select an Option] → target SObject (if known) → standard seeds.
     * @param {string|null} targetSObjectApiName  API name resolved from the criteria record
     */
    _buildSystemVariableOptions(targetSObjectApiName) {
        const options = [BLANK_OPTION];
        if (targetSObjectApiName) {
            options.push({ label: targetSObjectApiName, value: targetSObjectApiName });
        }
        SYSTEM_VARIABLE_SEEDS.forEach(seed => options.push({ label: seed, value: seed }));
        this.systemVariableOptions = options;
        this.consoleLog('_buildSystemVariableOptions', {
            targetSObj  : targetSObjectApiName,
            totalOptions: options.length
        });
    }

    /**
     * @description Calls getObjectFields() imperatively and rebuilds fieldOptions.
     *              For the target SObject the label format is "Field Label (apiName)".
     *              For all other objects (Organization, User, etc.) only the apiName is shown.
     * @param {string}  sysVarApiName    API name of the SObject whose fields to load
     * @param {boolean} isTargetSObject  true = show "label (apiName)", false = apiName only
     */
    _loadFieldsForSystemVariable(sysVarApiName, isTargetSObject) {
        this.toggleSpinner(1);

        apexGetObjectFields({ objectApiName: sysVarApiName })
            .then(response => {
                const rawFields = response.responseData
                    ? JSON.parse(response.responseData) : [];
                this.fieldOptions = [
                    BLANK_OPTION,
                    ...rawFields
                        .sort((a, b) => a.apiName.localeCompare(b.apiName))
                        .map(f => ({
                            label : isTargetSObject ? `${f.label} (${f.apiName})` : f.apiName,
                            value : f.apiName
                        }))
                ];
                this.consoleLog('_loadFieldsForSystemVariable — loaded', {
                    object    : sysVarApiName,
                    count     : rawFields.length,
                    withLabels: isTargetSObject
                });
            })
            .catch(error => {
                // Some global variable names (e.g. Setup, System) are not describable SObjects.
                // Leave the existing field options unchanged rather than clearing them.
                this.consoleLog('_loadFieldsForSystemVariable — error (fields unchanged)', error);
            })
            .finally(() => this.toggleSpinner(-1));
    }

    /**
     * @description Calls getFieldValue() imperatively to load the current
     *              formula string from the record and store it in both
     *              currentFormulaValue and originalFormulaValue.
     */
    _loadFieldValue() {
        this.toggleSpinner(1);

        apexGetFieldValue({
            objectApiName : this._storageObjectApiName,
            fieldApiName  : this.targetFieldApiName,
            recordId      : this.recordId
        })
        .then(response => {
            const value = response.responseData != null ? response.responseData : '';
            this.currentFormulaValue  = value;
            this.originalFormulaValue = value;
            this.consoleLog('_loadFieldValue — loaded', { length: value.length });
        })
        .catch(error => {
            this.consoleLog('_loadFieldValue — error', error);
            this._showToast('error', 'Load Error', getErrorMessage(error));
        })
        .finally(() => {
            this.toggleSpinner(-1);
        });
    }

    // ─── Edit Mode Event Handlers ─────────────────────────────────────────────

    /**
     * @description Activates edit mode when the user clicks the Edit button.
     *              Clears any stale verify state from a previous edit session.
     */
    handleEditOnclick() {
        this.isEditMode        = true;
        this.isVerifyModalOpen = false;
        this.verifyModalResult = null;
        this._verifyRecordId   = '';
        this.consoleLog('handleEditOnclick — edit mode activated');
    }

    /**
     * @description Deactivates edit mode and reverts currentFormulaValue to the
     *              last saved / loaded snapshot.
     */
    handleCancelOnclick() {
        this.isEditMode           = false;
        this.isVerifyModalOpen    = false;
        this.currentFormulaValue  = this.originalFormulaValue;
        this.verifyModalResult    = null;
        this._verifyRecordId      = '';
        this.consoleLog('handleCancelOnclick — reverted to original, edit mode deactivated');
    }

    /**
     * @description Validates the formula syntax via Apex before persisting.
     *              If the syntax check fails the save is aborted and an error
     *              toast is shown so the user can correct the formula first.
     *              On successful validation + save: updates originalFormulaValue,
     *              exits edit mode, and shows a success toast.
     */
    handleUpdateOnclick() {
        this.toggleSpinner(1);

        // ── Step 1: syntax check ─────────────────────────────────────────────
        apexVerifyFormula({
            formula       : this.currentFormulaValue,
            objectApiName : this._targetSObjectApiName,
            recordId      : null   // syntax-only; no record context needed here
        })
        .then(verifyResponse => {
            const res = verifyResponse.responseData
                ? JSON.parse(verifyResponse.responseData) : {};

            if (!res.isValid) {
                // Block the save — surface the syntax error as a toast
                this._showToast(
                    'error',
                    'Formula Syntax Error',
                    `Cannot save — ${res.errorMessage || 'formula syntax is invalid.'}`
                );
                this.consoleLog('handleUpdateOnclick — blocked by invalid formula', res);
                return Promise.reject({ _blocked: true });
            }

            // ── Step 2: persist ──────────────────────────────────────────────
            return apexUpdateFieldValue({
                objectApiName : this._storageObjectApiName,
                fieldApiName  : this.targetFieldApiName,
                recordId      : this.recordId,
                formulaValue  : this.currentFormulaValue
            });
        })
        .then(() => {
            this.originalFormulaValue = this.currentFormulaValue;
            this.isEditMode           = false;
            this.cacheIdx             = initCacheIdx(this.cacheIdx);
            this._showToast('success', 'Success', 'Formula updated successfully.');
            this.consoleLog('handleUpdateOnclick — updated successfully');
        })
        .catch(error => {
            // _blocked errors have already been toasted above; skip re-toasting
            if (error && error._blocked) { return; }
            this.consoleLog('handleUpdateOnclick — error (staying in edit mode)', error);
            this._showToast('error', 'Save Error', getErrorMessage(error));
        })
        .finally(() => {
            this.toggleSpinner(-1);
        });
    }

    // ─── Formula Textarea Handler ─────────────────────────────────────────────

    /**
     * @description Keeps currentFormulaValue in sync when the user edits the
     *              formula textarea directly.  lightning-textarea fires onchange
     *              on blur and exposes the value via event.detail.value.
     * @param {Event} event onchange event from lightning-textarea
     */
    handleFormulaChange(event) {
        this.currentFormulaValue = event.detail.value;
    }

    // ─── Combobox Insertion Handlers ─────────────────────────────────────────

    /**
     * @description Inserts the selected System Variable / Custom Metadata Type
     *              name at the current cursor position and resets the combobox.
     * @param {Event} event onchange event from the System Variables combobox
     */
    handleSystemVariableSelect(event) {
        const value = event.detail.value;
        if (!value) { return; }
        this._insertAtCursor(value);
        this._selectedSystemVariable = '';
        // Update Fields combobox to show fields for the selected system variable
        const isTargetSObject = value === this._targetSObjectApiName;
        this._loadFieldsForSystemVariable(value, isTargetSObject);
        this.consoleLog('handleSystemVariableSelect', { inserted: value, isTargetSObject });
    }

    /**
     * @description Inserts the selected field API name at the current cursor
     *              position and resets the combobox.
     * @param {Event} event onchange event from the Fields combobox
     */
    handleFieldSelect(event) {
        const value = event.detail.value;
        if (!value) { return; }
        this._insertAtCursor(value);
        this._selectedField = '';
        this.consoleLog('handleFieldSelect', { inserted: value });
    }

    /**
     * @description Inserts the selected function name (with opening parenthesis)
     *              at the current cursor position and resets the combobox.
     * @param {Event} event onchange event from the Functions combobox
     */
    handleFunctionSelect(event) {
        const value = event.detail.value;
        if (!value) { return; }
        this._insertAtCursor(value);
        this._selectedFunction = '';
        this.consoleLog('handleFunctionSelect', { inserted: value });
    }

    /**
     * @description Inserts the selected operator token at the current cursor
     *              position and resets the combobox.
     * @param {Event} event onchange event from the Operators combobox
     */
    handleOperatorSelect(event) {
        const value = event.detail.value;
        if (!value) { return; }
        this._insertAtCursor(value);
        this._selectedOperator = '';
        this.consoleLog('handleOperatorSelect', { inserted: value });
    }

    // ─── Verify Formula Modal Handlers ────────────────────────────────────────

    /**
     * @description Opens the Verify Formula modal.  Previous result and record Id
     *              are preserved so the user can see the last result immediately
     *              on re-open (unless the formula changed, which resets them).
     */
    handleVerifyOnclick() {
        this.isVerifyModalOpen = true;
        this.consoleLog('handleVerifyOnclick — modal opened');
    }

    /**
     * @description Closes the Verify Formula modal.  Does NOT clear the verified
     *              flag — a valid result persists so the Update button stays enabled
     *              after the modal is closed.
     */
    handleVerifyClose() {
        this.isVerifyModalOpen = false;
        this.consoleLog('handleVerifyClose — modal closed');
    }

    /**
     * @description Keeps _verifyRecordId in sync as the user types in the modal
     *              record Id input.  Does NOT trigger verification — the user must
     *              click the Verify button to run the check explicitly.
     * @param {Event} event onchange event from lightning-input
     */
    handleVerifyRecordInput(event) {
        this._verifyRecordId = (event.detail.value || '').trim();
        this.consoleLog('handleVerifyRecordInput', { recordId: this._verifyRecordId });
    }

    /**
     * @description Triggered by the "Verify" button in the modal footer.
     *              Runs (or re-runs) the syntax check with the current formula text
     *              and the record Id already stored in _verifyRecordId.
     */
    handleVerifyRecord() {
        this.consoleLog('handleVerifyRecord', { recordId: this._verifyRecordId });
        this._runVerify();
    }

    /**
     * @description Calls verifyFormula() imperatively and updates verifyModalResult.
     *              Called by the explicit Verify button inside the modal.
     *              The record Id is optional — Apex performs syntax-only checks
     *              regardless of whether a valid Id is supplied.
     */
    _runVerify() {
        this.verifyModalResult = null;
        this.toggleSpinner(1);

        apexVerifyFormula({
            formula       : this.currentFormulaValue,
            objectApiName : this.targetObjectApiName,
            recordId      : this._verifyRecordId || null
        })
        .then(response => {
            const res = response.responseData ? JSON.parse(response.responseData) : {};
            this.verifyModalResult = {
                isValid : res.isValid,
                message : res.isValid
                    ? 'Formula syntax is valid.'
                    : res.errorMessage
            };
            this.consoleLog('_runVerify — result', this.verifyModalResult);
        })
        .catch(error => {
            this.verifyModalResult = null;
            this.consoleLog('_runVerify — error', error);
            this._showToast('error', 'Verify Error', getErrorMessage(error));
        })
        .finally(() => {
            this.toggleSpinner(-1);
        });
    }

    // ─── Refresh Handler ─────────────────────────────────────────────────────

    /**
     * @description Reloads the formula value and resets all combobox selections
     *              back to the blank placeholder.  Called both by the Refresh
     *              icon button in the card header and by lightning/refresh.
     */
    handleRefresh() {
        this.consoleLog('handleRefresh — refreshing formula value and resetting selections');
        // Reset all insertion-combobox selections to blank
        this._selectedSystemVariable = '';
        this._selectedField          = '';
        this._selectedFunction       = '';
        this._selectedOperator       = '';
        // Restore Fields combobox to the target SObject's fields (default state)
        if (this._targetSObjectApiName) {
            this._loadFieldsForSystemVariable(this._targetSObjectApiName, true);
        }
        if (this.isConfigured) {
            this._loadFieldValue();
        }
    }

    // ─── Computed Getters ─────────────────────────────────────────────────────

    /**
     * @description True when both targetObjectApiName and targetFieldApiName are
     *              set — gates data-load calls and action buttons.
     * @return {boolean}
     */
    get isConfigured() {
        return !!(this.targetObjectApiName && this.targetFieldApiName);
    }

    /**
     * @description Sub-header label shown above the formula textarea in edit
     *              mode to confirm which field is being modified.
     * @return {string} e.g. "Formula for Study_Requirement_Set__c.Criteria__c"
     */
    get formulaTargetLabel() {
        const obj = this._storageObjectApiName || this.targetObjectApiName;
        return (obj && this.targetFieldApiName)
            ? `Formula for ${obj}.${this.targetFieldApiName}`
            : '';
    }

    /**
     * @description Card title changes between view and edit mode to match the
     *              wizard design.
     * @return {string}
     */
    get cardTitle() {
        return this.isEditMode
            ? 'Formula Builder - With Object and Field'
            : 'Formula Builder';
    }

    /**
     * @description True once connectedCallback has completed synchronous setup.
     *              Used by the template to gate the main card rendering until the
     *              component is fully initialised (spinner still shows independently).
     * @return {boolean}
     */
    get isInitSuccess() {
        return this._initComplete;
    }

    /**
     * @description True when the Edit button should be rendered.
     *              Requires allowEdit = true, isConfigured = true, and the
     *              component must not already be in edit mode.
     * @return {boolean}
     */
    get showEditButton() {
        return this.allowEdit && this.isConfigured && !this.isEditMode;
    }

    /**
     * @description True when the Update button should be disabled.
     *              Disabled only while an async operation is in flight — verification
     *              is opt-in and does not gate the Update action.
     * @return {boolean}
     */
    get isUpdateDisabled() {
        return this.isLoading;
    }

    /**
     * @description True when the Verify modal contains a result to display.
     * @return {boolean}
     */
    get hasVerifyModalResult() {
        return this.verifyModalResult !== null;
    }

    /**
     * @description True when the last verifyFormula call returned isValid = true.
     *              Used by if:true in the template to show the success block.
     * @return {boolean}
     */
    get verifyModalIsValid() {
        return !!(this.verifyModalResult && this.verifyModalResult.isValid);
    }

    /**
     * @description True when a result exists and isValid = false.
     *              Used by if:true in the template to show the error block.
     * @return {boolean}
     */
    get verifyModalIsInvalid() {
        return this.hasVerifyModalResult && !this.verifyModalResult.isValid;
    }

    /**
     * @description Human-readable verify-result message for display in the modal.
     * @return {string}
     */
    get verifyModalResultMessage() {
        return this.verifyModalResult ? this.verifyModalResult.message : '';
    }

    // ─── Private Helpers ─────────────────────────────────────────────────────

    /**
     * @description Inserts `token` at the current cursor position in the formula
     *              textarea, or appends it to the end if the textarea is not
     *              focused or the cursor is at position 0 with existing content
     *              (which indicates no active selection rather than a genuine
     *              front-of-string intent).
     *
     *              After updating currentFormulaValue it sets _pendingCursorPos
     *              so that renderedCallback can reposition the cursor once the
     *              DOM has re-rendered.
     *
     * @param {string} token The text to insert (e.g. ' AND ', 'IF(', ' + ')
     */
    _insertAtCursor(token) {
        const el      = this.template.querySelector('[data-id="formulaTextarea"]');
        const current = this.currentFormulaValue || '';

        // selectionStart is a numeric property only on native <textarea> / <input>
        // elements.  lightning-textarea wraps its inner element in shadow DOM that
        // is inaccessible from the parent component, so typeof check distinguishes
        // between the two cases and prevents "NaN"-based substring corruption.
        const hasNativeCursor = el && typeof el.selectionStart === 'number';

        if (hasNativeCursor) {
            const rawStart = el.selectionStart;
            const rawEnd   = el.selectionEnd;

            // If both positions are 0 and the formula already has content the
            // textarea has probably never received focus — append to end instead
            // of silently inserting at the very beginning.
            const atStart = rawStart === 0 && rawEnd === 0 && current.length > 0;
            const start   = atStart ? current.length : rawStart;
            const end     = atStart ? current.length : rawEnd;

            this.currentFormulaValue = current.substring(0, start) + token + current.substring(end);
            this._pendingCursorPos   = start + token.length;
        } else {
            // lightning-textarea, view-mode, or no element in DOM — append to end
            this.currentFormulaValue = current + token;
            this._pendingCursorPos   = undefined; // no cursor to restore
        }
    }

    /**
     * @description Dispatches a Lightning ShowToastEvent with auto-dismiss.
     *              mode='pester' causes the platform to auto-close the toast
     *              after ~3 s so it never gets stuck on screen.
     * @param {'success'|'error'|'warning'|'info'} variant
     * @param {string} title   Bold heading shown at the top of the toast
     * @param {string} message Detail text shown below the title
     */
    _showToast(variant, title, message) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant,
            mode : 'pester'   // auto-dismiss — never sticks on screen
        }));
    }

    /**
     * @description Increments or decrements the spinner depth counter and
     *              updates the reactive isLoading flag.
     *              Call toggleSpinner(1) before every async operation and
     *              toggleSpinner(-1) in its finally block.
     * @param {number} increment +1 to start loading, -1 to finish
     */
    toggleSpinner(increment) {
        this._spinnerCount += increment;
        this.isLoading = this._spinnerCount > 0;
    }

    /**
     * @description Wrapper for logInfo (c/loggingUtil) that prepends the
     *              component name to every log entry.  Emits only when
     *              enableDebugMode is true so production orgs stay clean.
     * @param {string} message Short description of the log entry
     * @param {*}      data    Optional payload attached to the log line
     */
    consoleLog(message, data) {
        if (this.enableDebugMode) {
            logInfo(COMPONENT, message, data);
        }
    }
}
