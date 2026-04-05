/**
 * @Author      WDCi ()
 * @Date        April 2026
 * @group       Formula Builder
 * @Description JavaScript controller for the formulaBuilder LWC.
 *              Provides a full formula-editing experience: view mode shows the
 *              current formula value with an Edit button; edit mode exposes four
 *              comboboxes (System Variables, Fields, Functions, Operators) that
 *              insert tokens at the current cursor position, a live-editable
 *              formula textarea, a Verify modal backed by the Apex syntax
 *              checker, and an Update / Cancel action pair.
 *
 *              All Apex calls are imperative. getObjectInfo wire populates the
 *              Fields combobox reactively from the configured object.
 * @changehistory
 * ISS-002768 2026-04-03 - Initial development of Formula Builder LWC JavaScript controller
 */
import { LightningElement, api, track, wire } from 'lwc';
import { getObjectInfo }                       from 'lightning/uiObjectInfoApi';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';

import { promptSuccess, promptError, promptWarning } from 'c/toasterUtil';
import { getErrorMessage, logInfo }                  from 'c/loggingUtil';
import { initCacheIdx }                              from 'c/lwcUtil';

import apexGetFieldValue      from '@salesforce/apex/REDU_FormulaBuilder_LCTRL.getFieldValue';
import apexUpdateFieldValue   from '@salesforce/apex/REDU_FormulaBuilder_LCTRL.updateFieldValue';
import apexGetCustomMetaTypes from '@salesforce/apex/REDU_FormulaBuilder_LCTRL.getCustomMetadataTypes';
import apexVerifyFormula      from '@salesforce/apex/REDU_FormulaBuilder_LCTRL.verifyFormula';

// ─── Component identifier for log statements ──────────────────────────────────
const COMPONENT = 'formulaBuilder';

// ─── Hardcoded system-variable seeds (merged with org Custom Metadata Types) ──
const SYSTEM_VARIABLE_SEEDS = [
    'Organization', 'Permission', 'Profile', 'Setup', 'System', 'User', 'UserRole'
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

    // ─── Private State ────────────────────────────────────────────────────────

    /** Depth counter for nested async calls — spinner shows when > 0 */
    _spinnerCount = 0;

    /** Token returned by registerRefreshHandler */
    _refreshHandler;

    /**
     * @description Pending cursor position to restore after a combobox insertion
     *              causes the textarea to re-render with a new value.
     *              Set by _insertAtCursor; consumed and cleared in renderedCallback.
     */
    _pendingCursorPos = undefined;

    /** Cache-buster incremented by initCacheIdx to signal data reload */
    cacheIdx = 0;

    // ─── Wire: Object Info ────────────────────────────────────────────────────

    /**
     * @description Reactively fetches field metadata whenever targetObjectApiName
     *              changes.  Populates fieldOptions and resolves fieldLabel for
     *              the configured targetFieldApiName.
     * @param {Object} wireResult Standard LWC wire result { data, error }
     */
    @wire(getObjectInfo, { objectApiName: '$targetObjectApiName' })
    wiredObjectInfo({ error, data }) {
        if (data) {
            this.consoleLog('wiredObjectInfo — received data', { objectApiName: this.targetObjectApiName });
            const fields = data.fields;

            // Resolve the display label for the target field (shown in view mode)
            if (this.targetFieldApiName && fields[this.targetFieldApiName]) {
                this.fieldLabel = fields[this.targetFieldApiName].label;
            }

            // Build sorted combobox options: "label (apiName)"
            this.fieldOptions = [
                BLANK_OPTION,
                ...Object.keys(fields)
                    .sort()
                    .map(apiName => ({
                        label : `${fields[apiName].label} (${apiName})`,
                        value : apiName
                    }))
            ];
        } else if (error) {
            // Field list unavailable — log only; do not surface error toast
            this.consoleLog('wiredObjectInfo — error (fields combobox will be empty)', error);
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

        // Async: merge org Custom MDTs into System Variables combobox
        this._loadCustomMetadataTypes();

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
     */
    renderedCallback() {
        if (this._pendingCursorPos !== undefined) {
            const textarea = this.template.querySelector('[data-id="formulaTextarea"]');
            if (textarea) {
                textarea.focus();
                textarea.setSelectionRange(this._pendingCursorPos, this._pendingCursorPos);
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
     * @description Calls getCustomMetadataTypes() imperatively and merges the
     *              returned __mdt API names with the hardcoded SYSTEM_VARIABLE_SEEDS
     *              into systemVariableOptions.  Falls back to seeds only on error.
     */
    _loadCustomMetadataTypes() {
        this.toggleSpinner(1);

        apexGetCustomMetaTypes()
            .then(response => {
                const mdtNames  = Array.isArray(response.data) ? response.data : [];
                const combined  = [
                    ...SYSTEM_VARIABLE_SEEDS.map(s => ({ label: s, value: s })),
                    ...mdtNames.map(name => ({ label: name, value: name }))
                ];

                // Deduplicate (seed names take precedence) and sort alphabetically
                const seen   = new Set();
                const unique = combined.filter(opt => {
                    if (seen.has(opt.value)) { return false; }
                    seen.add(opt.value);
                    return true;
                });
                unique.sort((a, b) => a.label.localeCompare(b.label));

                this.systemVariableOptions = [BLANK_OPTION, ...unique];
                this.consoleLog('_loadCustomMetadataTypes — loaded', {
                    totalOptions : unique.length,
                    mdtCount     : mdtNames.length
                });
            })
            .catch(error => {
                this.consoleLog('_loadCustomMetadataTypes — error, falling back to seeds', error);
                // Fall back to hardcoded seeds so the combobox is still usable
                this.systemVariableOptions = [
                    BLANK_OPTION,
                    ...SYSTEM_VARIABLE_SEEDS.map(s => ({ label: s, value: s }))
                ];
                promptWarning(
                    this,
                    'Could not load Custom Metadata Types. Showing built-in system variables only.'
                );
            })
            .finally(() => {
                this.toggleSpinner(-1);
            });
    }

    /**
     * @description Calls getFieldValue() imperatively to load the current
     *              formula string from the record and store it in both
     *              currentFormulaValue and originalFormulaValue.
     */
    _loadFieldValue() {
        this.toggleSpinner(1);

        apexGetFieldValue({
            objectApiName : this.targetObjectApiName,
            fieldApiName  : this.targetFieldApiName,
            recordId      : this.recordId
        })
        .then(response => {
            const value = response.data != null ? response.data : '';
            this.currentFormulaValue  = value;
            this.originalFormulaValue = value;
            this.consoleLog('_loadFieldValue — loaded', { length: value.length });
        })
        .catch(error => {
            this.consoleLog('_loadFieldValue — error', error);
            promptError(this, getErrorMessage(error));
        })
        .finally(() => {
            this.toggleSpinner(-1);
        });
    }

    // ─── Edit Mode Event Handlers ─────────────────────────────────────────────

    /**
     * @description Activates edit mode when the user clicks the Edit button.
     */
    handleEditOnclick() {
        this.isEditMode = true;
        this.consoleLog('handleEditOnclick — edit mode activated');
    }

    /**
     * @description Deactivates edit mode and reverts currentFormulaValue to the
     *              last saved / loaded snapshot.
     */
    handleCancelOnclick() {
        this.isEditMode           = false;
        this.currentFormulaValue  = this.originalFormulaValue;
        this.consoleLog('handleCancelOnclick — reverted to original, edit mode deactivated');
    }

    /**
     * @description Saves the current formula value to the record via
     *              updateFieldValue().  On success: updates originalFormulaValue,
     *              exits edit mode, and shows a success toast.  On error: stays
     *              in edit mode and shows an error toast.
     */
    handleUpdateOnclick() {
        this.toggleSpinner(1);

        apexUpdateFieldValue({
            objectApiName : this.targetObjectApiName,
            fieldApiName  : this.targetFieldApiName,
            recordId      : this.recordId,
            formulaValue  : this.currentFormulaValue
        })
        .then(() => {
            this.originalFormulaValue = this.currentFormulaValue;
            this.isEditMode           = false;
            this.cacheIdx             = initCacheIdx(this.cacheIdx);
            promptSuccess(this, 'Formula updated successfully.');
            this.consoleLog('handleUpdateOnclick — updated successfully');
        })
        .catch(error => {
            this.consoleLog('handleUpdateOnclick — error (staying in edit mode)', error);
            promptError(this, getErrorMessage(error));
        })
        .finally(() => {
            this.toggleSpinner(-1);
        });
    }

    // ─── Formula Textarea Handler ─────────────────────────────────────────────

    /**
     * @description Keeps currentFormulaValue in sync as the user types directly
     *              in the formula textarea.
     * @param {Event} event oninput event from the formula textarea
     */
    handleFormulaInput(event) {
        this.currentFormulaValue = event.target.value;
    }

    // ─── Combobox Insertion Handlers ─────────────────────────────────────────

    /**
     * @description Inserts the selected System Variable / Custom Metadata Type
     *              name at the current cursor position and resets the combobox.
     * @param {Event} event onchange event from the System Variables combobox
     */
    handleSystemVariableChange(event) {
        const value = event.detail.value;
        if (!value) { return; }
        this._insertAtCursor(value);
        this._selectedSystemVariable = '';
        this.consoleLog('handleSystemVariableChange', { inserted: value });
    }

    /**
     * @description Inserts the selected field API name at the current cursor
     *              position and resets the combobox.
     * @param {Event} event onchange event from the Fields combobox
     */
    handleFieldChange(event) {
        const value = event.detail.value;
        if (!value) { return; }
        this._insertAtCursor(value);
        this._selectedField = '';
        this.consoleLog('handleFieldChange', { inserted: value });
    }

    /**
     * @description Inserts the selected function name (with opening parenthesis)
     *              at the current cursor position and resets the combobox.
     * @param {Event} event onchange event from the Functions combobox
     */
    handleFunctionChange(event) {
        const value = event.detail.value;
        if (!value) { return; }
        this._insertAtCursor(value);
        this._selectedFunction = '';
        this.consoleLog('handleFunctionChange', { inserted: value });
    }

    /**
     * @description Inserts the selected operator token at the current cursor
     *              position and resets the combobox.
     * @param {Event} event onchange event from the Operators combobox
     */
    handleOperatorChange(event) {
        const value = event.detail.value;
        if (!value) { return; }
        this._insertAtCursor(value);
        this._selectedOperator = '';
        this.consoleLog('handleOperatorChange', { inserted: value });
    }

    // ─── Verify Formula Modal Handlers ────────────────────────────────────────

    /**
     * @description Opens the Verify Formula modal and clears any previous result.
     */
    handleVerifyOnclick() {
        this.isVerifyModalOpen = true;
        this.verifyModalResult = null;
        this.consoleLog('handleVerifyOnclick — modal opened');
    }

    /**
     * @description Closes the Verify Formula modal without saving.
     */
    handleVerifyClose() {
        this.isVerifyModalOpen = false;
        this.verifyModalResult = null;
        this.consoleLog('handleVerifyClose — modal closed');
    }

    /**
     * @description Receives a sample record selection from the modal's record
     *              picker, calls verifyFormula() imperatively with the current
     *              formula and the selected record as context, and stores the
     *              result for display inside the modal.
     *
     *              Supports both lightning-record-picker (event.detail.recordId)
     *              and lightning-combobox / custom (event.detail.value) event
     *              shapes so the modal template can use either input pattern.
     *
     * @param {Event} event Custom or standard change event carrying the recordId
     */
    handleVerifyRecord(event) {
        // Normalise across lightning-record-picker and plain-combobox event shapes
        const sampleRecordId =
            (event.detail && (event.detail.recordId || event.detail.value)) || '';

        if (!sampleRecordId) {
            this.verifyModalResult = null;
            return;
        }

        this.toggleSpinner(1);
        this.verifyModalResult = null;

        apexVerifyFormula({
            formula       : this.currentFormulaValue,
            objectApiName : this.targetObjectApiName,
            recordId      : sampleRecordId
        })
        .then(response => {
            const res = response.data;
            this.verifyModalResult = {
                isValid : res.isValid,
                message : res.isValid
                    ? 'Formula syntax is valid.'
                    : res.errorMessage
            };
            this.consoleLog('handleVerifyRecord — result', this.verifyModalResult);
        })
        .catch(error => {
            this.consoleLog('handleVerifyRecord — error', error);
            promptError(this, getErrorMessage(error));
        })
        .finally(() => {
            this.toggleSpinner(-1);
        });
    }

    // ─── Refresh Handler ─────────────────────────────────────────────────────

    /**
     * @description Invoked by lightning/refresh (e.g. after a sibling component
     *              saves the record).  Reloads the formula value if configured.
     */
    handleRefresh() {
        this.consoleLog('handleRefresh — refreshing formula value');
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
        return this.isConfigured
            ? `Formula for ${this.targetObjectApiName}.${this.targetFieldApiName}`
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
     * @description True when the Edit button should be rendered (allowEdit prop
     *              is set and the component is not already in edit mode).
     * @return {boolean}
     */
    get showEditButton() {
        return this.allowEdit && !this.isEditMode;
    }

    /**
     * @description True when the Verify Formula modal contains a result to display.
     * @return {boolean}
     */
    get hasVerifyModalResult() {
        return this.verifyModalResult !== null;
    }

    /**
     * @description CSS class string for the verify-result banner inside the
     *              modal — toggles between success (green) and error (red) states.
     * @return {string}
     */
    get verifyModalResultClass() {
        const base = 'formula-builder-verify-banner slds-box slds-p-around_small slds-m-top_small';
        if (!this.verifyModalResult) { return base; }
        return this.verifyModalResult.isValid
            ? `${base} formula-builder-verify-banner--success`
            : `${base} formula-builder-verify-banner--error`;
    }

    /**
     * @description SLDS icon name for the verify-result banner.
     * @return {string}
     */
    get verifyModalResultIcon() {
        return this.verifyModalResult && this.verifyModalResult.isValid
            ? 'utility:success'
            : 'utility:error';
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
        const textarea = this.template.querySelector('[data-id="formulaTextarea"]');
        const current  = this.currentFormulaValue || '';

        if (textarea) {
            const rawStart = textarea.selectionStart;
            const rawEnd   = textarea.selectionEnd;

            // When both start and end are 0 and the formula has existing content
            // the textarea likely has no active cursor (never focused); treat
            // this as "append to end" to avoid silently inserting at position 0.
            const atStart = rawStart === 0 && rawEnd === 0 && current.length > 0;
            const start   = atStart ? current.length : rawStart;
            const end     = atStart ? current.length : rawEnd;

            this.currentFormulaValue = current.substring(0, start) + token + current.substring(end);
            this._pendingCursorPos   = start + token.length;
        } else {
            // Textarea not in DOM (e.g. view mode) — append to end
            this.currentFormulaValue = current + token;
            this._pendingCursorPos   = current.length + token.length;
        }
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
