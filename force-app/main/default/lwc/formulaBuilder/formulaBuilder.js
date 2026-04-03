/**
 * @Author      WDCi ()
 * @Date        April 2026
 * @group       Formula Builder
 * @Description JavaScript controller for the formulaBuilder LWC.
 *              Provides a rich formula-editing experience: loads the current
 *              field value via wire, supports operator quick-insert and Custom
 *              Metadata Type insertion, verifies formula syntax, and persists
 *              changes back to the record via imperative Apex calls.
 * @changehistory
 * ISS-002768 2026-04-03 - Initial development of Formula Builder LWC JavaScript controller
 */
import { LightningElement, api, track, wire } from 'lwc';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';

import { promptSuccess, promptError, promptWarning }  from 'c/toasterUtil';
import { getErrorMessage, logInfo }                   from 'c/loggingUtil';
import { initCacheIdx }                               from 'c/lwcUtil';

import apexGetFieldValue        from '@salesforce/apex/REDU_FormulaBuilder_LCTRL.getFieldValue';
import apexUpdateFieldValue     from '@salesforce/apex/REDU_FormulaBuilder_LCTRL.updateFieldValue';
import apexGetCustomMetaTypes   from '@salesforce/apex/REDU_FormulaBuilder_LCTRL.getCustomMetadataTypes';
import apexVerifyFormula        from '@salesforce/apex/REDU_FormulaBuilder_LCTRL.verifyFormula';

// ─── Component identifier used in log statements ───────────────────────────
const COMPONENT = 'formulaBuilder';

// ─── Operator tokens available in the toolbar ──────────────────────────────
const OPERATORS = [
    { label: 'AND',  value: ' AND ',  variant: 'neutral', title: 'Logical AND' },
    { label: 'OR',   value: ' OR ',   variant: 'neutral', title: 'Logical OR' },
    { label: 'NOT',  value: ' NOT ',  variant: 'neutral', title: 'Logical NOT' },
    { label: '(',    value: '(',      variant: 'neutral', title: 'Open parenthesis' },
    { label: ')',    value: ')',      variant: 'neutral', title: 'Close parenthesis' },
    { label: '=',    value: ' = ',    variant: 'neutral', title: 'Equal to' },
    { label: '!=',   value: ' != ',   variant: 'neutral', title: 'Not equal to' },
    { label: '>',    value: ' > ',    variant: 'neutral', title: 'Greater than' },
    { label: '>=',   value: ' >= ',   variant: 'neutral', title: 'Greater than or equal' },
    { label: '<',    value: ' < ',    variant: 'neutral', title: 'Less than' },
    { label: '<=',   value: ' <= ',   variant: 'neutral', title: 'Less than or equal' }
];

export default class FormulaBuilder extends LightningElement {

    // ─── Public API Properties ──────────────────────────────────────────────

    /**
     * @description Salesforce record Id whose field value will be loaded and saved
     */
    @api recordId;

    /**
     * @description API name of the object (e.g. Study_Requirement_Set__c)
     */
    @api objectApiName;

    /**
     * @description API name of the field holding the formula (e.g. Criteria__c)
     */
    @api fieldApiName;

    /**
     * @description Optional heading shown in the card title area
     */
    @api cardTitle = 'Formula Builder';

    // ─── Tracked State ──────────────────────────────────────────────────────

    /** Current formula text shown in the editor */
    @track formulaValue = '';

    /** Snapshot of the formula at last load/save — used for Cancel */
    @track originalFormulaValue = '';

    /** Combobox options built from Custom Metadata Type names */
    @track metadataTypeOptions = [];

    /** Currently selected metadata type in the combobox */
    @track selectedMetadataType = '';

    /** Controls the loading spinner visibility */
    @track isLoading = false;

    /** Holds the last verify result: { isValid, message } or null */
    @track verifyResult = null;

    // ─── Private State ──────────────────────────────────────────────────────

    /** Running spinner depth counter — spinner shows when > 0 */
    _spinnerCount = 0;

    /** Token returned by registerRefreshHandler */
    _refreshHandler;

    /**
     * @description Reactive cache-buster passed to wire adapters that support
     *              forced refresh via initCacheIdx from c/lwcUtil
     */
    cacheIdx = 0;

    // ─── Lifecycle Hooks ────────────────────────────────────────────────────

    /**
     * @description Registers the standard refresh handler so external refresh
     *              events (e.g. from lightning/refresh) re-load the formula value
     */
    connectedCallback() {
        this._refreshHandler = registerRefreshHandler(
            this,
            this.handleRefresh.bind(this)
        );
        this.consoleLog('connectedCallback', { recordId: this.recordId, objectApiName: this.objectApiName, fieldApiName: this.fieldApiName });
    }

    /**
     * @description Cleans up the refresh handler on component removal
     */
    disconnectedCallback() {
        unregisterRefreshHandler(this._refreshHandler);
    }

    // ─── Wire Adapters ──────────────────────────────────────────────────────

    /**
     * @description Reactively loads the current formula value whenever
     *              recordId, objectApiName, or fieldApiName changes
     * @param {Object} wireResult Standard LWC wire result { data, error }
     */
    @wire(apexGetFieldValue, {
        objectApiName : '$objectApiName',
        fieldApiName  : '$fieldApiName',
        recordId      : '$recordId'
    })
    wiredFieldValue({ error, data }) {
        if (data) {
            this.consoleLog('wiredFieldValue — received data', data);
            this.formulaValue         = data.data != null ? data.data : '';
            this.originalFormulaValue = this.formulaValue;
        } else if (error) {
            this.consoleLog('wiredFieldValue — received error', error);
            promptError(this, getErrorMessage(error));
        }
    }

    /**
     * @description Loads all Custom Metadata Type API names once on mount;
     *              results populate the metadata-insert combobox
     * @param {Object} wireResult Standard LWC wire result { data, error }
     */
    @wire(apexGetCustomMetaTypes)
    wiredMetadataTypes({ error, data }) {
        if (data) {
            this.consoleLog('wiredMetadataTypes — received data', data);
            const names = Array.isArray(data.data) ? data.data : [];
            this.metadataTypeOptions = [
                { label: '— Select a Metadata Type —', value: '' },
                ...names.map(name => ({ label: name, value: name }))
            ];
        } else if (error) {
            this.consoleLog('wiredMetadataTypes — received error', error);
            promptError(this, getErrorMessage(error));
        }
    }

    // ─── Getters ────────────────────────────────────────────────────────────

    /**
     * @description Returns the static operator token list for the toolbar
     * @return {Array} operator descriptor objects
     */
    get operators() {
        return OPERATORS;
    }

    /**
     * @description True when a verify result is present and should be displayed
     * @return {boolean}
     */
    get hasVerifyResult() {
        return this.verifyResult !== null;
    }

    /**
     * @description CSS class string for the verify-result banner,
     *              toggles between success and error visual states
     * @return {string}
     */
    get verifyResultClass() {
        const base = 'formula-builder-verify-banner slds-box slds-m-top_small slds-p-around_small';
        if (!this.verifyResult) {
            return base;
        }
        return this.verifyResult.isValid
            ? `${base} formula-builder-verify-banner--success`
            : `${base} formula-builder-verify-banner--error`;
    }

    /**
     * @description Human-readable message from the last verify call
     * @return {string}
     */
    get verifyResultMessage() {
        return this.verifyResult ? this.verifyResult.message : '';
    }

    /**
     * @description Icon name for the verify-result banner
     * @return {string}
     */
    get verifyResultIcon() {
        return this.verifyResult && this.verifyResult.isValid
            ? 'utility:success'
            : 'utility:error';
    }

    /**
     * @description True when the formula has been modified from its original value,
     *              used to enable/disable the Save button
     * @return {boolean}
     */
    get isDirty() {
        return this.formulaValue !== this.originalFormulaValue;
    }

    /**
     * @description True when metadata combobox has no options yet (still loading)
     * @return {boolean}
     */
    get isMetadataLoading() {
        return this.metadataTypeOptions.length === 0;
    }

    // ─── Event Handlers ─────────────────────────────────────────────────────

    /**
     * @description Keeps formulaValue in sync with the textarea and clears
     *              any stale verify result
     * @param {Event} event change event from lightning-textarea or native textarea
     */
    handleFormulaChange(event) {
        this.formulaValue = event.target.value;
        this.verifyResult = null;
    }

    /**
     * @description Appends the clicked operator token to the current formula
     * @param {Event} event click event; operator value is on event.target.dataset.value
     */
    handleInsertOperator(event) {
        const token = event.currentTarget.dataset.value;
        this.formulaValue = (this.formulaValue || '') + token;
        this.verifyResult = null;
        this.consoleLog('handleInsertOperator', { token });
    }

    /**
     * @description Appends the selected Custom Metadata Type name to the formula
     *              and resets the combobox selection
     * @param {Event} event change event from lightning-combobox
     */
    handleMetadataTypeSelect(event) {
        const selectedName = event.detail.value;
        if (!selectedName) {
            return;
        }
        this.formulaValue      = (this.formulaValue || '') + selectedName;
        this.selectedMetadataType = '';
        this.verifyResult      = null;
        this.consoleLog('handleMetadataTypeSelect', { selectedName });
    }

    /**
     * @description Calls the Apex verifyFormula method and displays the result
     *              in the inline banner without saving
     */
    handleVerifyFormula() {
        this.toggleSpinner(1);
        this.verifyResult = null;

        apexVerifyFormula({
            formula       : this.formulaValue,
            objectApiName : this.objectApiName,
            recordId      : this.recordId
        })
        .then(response => {
            const res = response.data;
            this.verifyResult = {
                isValid : res.isValid,
                message : res.isValid
                    ? 'Formula syntax is valid.'
                    : res.errorMessage
            };
            this.consoleLog('handleVerifyFormula — result', this.verifyResult);

            if (!res.isValid) {
                promptWarning(this, res.errorMessage);
            }
        })
        .catch(error => {
            this.consoleLog('handleVerifyFormula — error', error);
            promptError(this, getErrorMessage(error));
        })
        .finally(() => {
            this.toggleSpinner(-1);
        });
    }

    /**
     * @description Persists the current formula value to the record via Apex,
     *              then refreshes the wire cache
     */
    handleSave() {
        if (!this.isDirty) {
            promptWarning(this, 'No changes to save.');
            return;
        }

        this.toggleSpinner(1);

        apexUpdateFieldValue({
            objectApiName : this.objectApiName,
            fieldApiName  : this.fieldApiName,
            recordId      : this.recordId,
            formulaValue  : this.formulaValue
        })
        .then(() => {
            this.originalFormulaValue = this.formulaValue;
            this.verifyResult         = null;
            this.cacheIdx             = initCacheIdx(this.cacheIdx);
            promptSuccess(this, 'Formula saved successfully.');
            this.consoleLog('handleSave — saved successfully');
        })
        .catch(error => {
            this.consoleLog('handleSave — error', error);
            promptError(this, getErrorMessage(error));
        })
        .finally(() => {
            this.toggleSpinner(-1);
        });
    }

    /**
     * @description Reverts the formula editor to the last saved/loaded value
     *              and clears any verify result
     */
    handleCancel() {
        this.formulaValue = this.originalFormulaValue;
        this.verifyResult = null;
        this.consoleLog('handleCancel — reverted to original');
    }

    /**
     * @description Invoked by lightning/refresh when an external event requests
     *              that the component reload its data
     */
    handleRefresh() {
        this.consoleLog('handleRefresh — refreshing wire cache');
        this.cacheIdx = initCacheIdx(this.cacheIdx);
    }

    // ─── Private Helpers ────────────────────────────────────────────────────

    /**
     * @description Increments or decrements the spinner counter and sets the
     *              isLoading flag accordingly. Use toggleSpinner(1) before an
     *              async operation and toggleSpinner(-1) in the finally block.
     * @param {number} increment +1 to start loading, -1 to finish
     */
    toggleSpinner(increment) {
        this._spinnerCount += increment;
        this.isLoading = this._spinnerCount > 0;
    }

    /**
     * @description Wrapper for logInfo that prefixes log entries with the
     *              component name for consistent console output
     * @param {string} message Short description of the log entry
     * @param {*}      data    Optional payload to include in the log
     */
    consoleLog(message, data) {
        logInfo(COMPONENT, message, data);
    }
}
