'use strict';
'require view';
'require dom';
'require poll';
'require rpc';
'require ui';

var callStatus = rpc.declare({
    object: 'wiglewrt',
    method: 'status'
});

var callGPS = rpc.declare({
    object: 'wiglewrt',
    method: 'gps_status'
});

var callNetworks = rpc.declare({
    object: 'wiglewrt',
    method: 'networks',
    params: ['limit', 'offset']
});

var callCurrentScan = rpc.declare({
    object: 'wiglewrt',
    method: 'current_scan',
    params: ['limit']
});

var callSessions = rpc.declare({
    object: 'wiglewrt',
    method: 'sessions_list'
});

var callSessionExport = rpc.declare({
    object: 'wiglewrt',
    method: 'session_export',
    params: ['session_id']
});

var callSessionDelete = rpc.declare({
    object: 'wiglewrt',
    method: 'session_delete',
    params: ['session_id']
});

var callStart = rpc.declare({
    object: 'wiglewrt',
    method: 'start',
    params: ['dwell']
});

var callStop = rpc.declare({
    object: 'wiglewrt',
    method: 'stop'
});

var callExport = rpc.declare({
    object: 'wiglewrt',
    method: 'export'
});

// State
var state = {
    pageSize: 50,
    currentPage: 0,
    dwell: 500,
    isRunning: false
};

return view.extend({
    load: function() {
        return Promise.all([
            callStatus(),
            callGPS(),
            callCurrentScan(state.pageSize),
            callSessions()
        ]);
    },

    render: function(data) {
        var status = data[0] || {};
        var gps = data[1] || {};
        var currentScan = data[2] || { total: 0, networks: [] };
        var sessions = data[3] || { sessions: [] };

        state.isRunning = status.running;

        var view = E('div', { 'class': 'cbi-map' }, [
            E('h2', {}, 'WigleWRT v2'),

            // Controls Section (moved to top)
            E('div', { 'class': 'cbi-section' }, [
                E('h3', {}, 'Controls'),
                E('div', { 'style': 'display: flex; gap: 10px; align-items: center; flex-wrap: wrap;' }, [
                    E('select', { 'id': 'dwell-select', 'class': 'cbi-input-select' }, [
                        E('option', { 'value': '100' }, '100ms (fast)'),
                        E('option', { 'value': '500', 'selected': 'selected' }, '500ms (recommended)'),
                        E('option', { 'value': '1000' }, '1000ms (thorough)')
                    ]),
                    E('button', {
                        'class': 'cbi-button cbi-button-apply',
                        'click': this.handleStart.bind(this),
                        'id': 'start-btn'
                    }, 'Start'),
                    E('button', {
                        'class': 'cbi-button cbi-button-reset',
                        'click': this.handleStop.bind(this),
                        'id': 'stop-btn'
                    }, 'Stop'),
                    E('button', {
                        'class': 'cbi-button cbi-button-action',
                        'click': this.handleExport.bind(this)
                    }, 'Export CSV')
                ])
            ]),

            // Status Section
            E('div', { 'class': 'cbi-section', 'id': 'status-section' }, [
                E('h3', {}, 'Status'),
                E('table', { 'class': 'table', 'style': 'width: auto; margin-bottom: 1em;' }, [
                    E('tr', { 'class': 'tr' }, [
                        E('td', { 'class': 'td', 'style': 'padding-right: 2em; font-weight: bold;' }, 'Scanner'),
                        E('td', { 'class': 'td', 'id': 'scanner-status' },
                            status.running ? 'Running' : 'Stopped')
                    ]),
                    E('tr', { 'class': 'tr' }, [
                        E('td', { 'class': 'td', 'style': 'padding-right: 2em; font-weight: bold;' }, 'Strategy'),
                        E('td', { 'class': 'td', 'id': 'scanner-strategy' },
                            status.strategy || 'none')
                    ]),
                    E('tr', { 'class': 'tr' }, [
                        E('td', { 'class': 'td', 'style': 'padding-right: 2em; font-weight: bold;' }, 'Networks'),
                        E('td', { 'class': 'td', 'id': 'network-count' },
                            String(status.networks || 0))
                    ]),
                    E('tr', { 'class': 'tr' }, [
                        E('td', { 'class': 'td', 'style': 'padding-right: 2em; font-weight: bold;' }, 'Rate'),
                        E('td', { 'class': 'td', 'id': 'scan-rate' },
                            status.rate || '0/s')
                    ]),
                    E('tr', { 'class': 'tr' }, [
                        E('td', { 'class': 'td', 'style': 'padding-right: 2em; font-weight: bold;' }, 'GPS'),
                        E('td', { 'class': 'td', 'id': 'gps-status' },
                            this.formatGPS(gps))
                    ])
                ])
            ]),

            // Current Scan Section (live network log)
            E('div', { 'class': 'cbi-section', 'id': 'current-scan-section' }, [
                E('h3', {}, ['Current Scan ', E('span', { 'id': 'current-scan-total' }, '(' + currentScan.total + ' sightings)')]),
                E('div', { 'id': 'current-scan-container' },
                    this.renderCurrentScanTable(currentScan.networks))
            ]),

            // Previous Scans Section
            E('div', { 'class': 'cbi-section', 'id': 'previous-scans-section' }, [
                E('h3', {}, 'Previous Scans'),
                E('div', { 'id': 'sessions-container' },
                    this.renderSessionsTable(sessions.sessions))
            ])
        ]);

        // Start polling
        poll.add(this.pollStatus.bind(this), 3);

        return view;
    },

    formatGPS: function(gps) {
        if (gps.fix) {
            return gps.lat.toFixed(6) + ', ' + gps.lon.toFixed(6) + ' (' + (gps.sats || 0) + ' sats)';
        } else {
            return 'No fix (' + (gps.sats || 0) + ' sats)';
        }
    },

    renderCurrentScanTable: function(networks) {
        if (!networks || networks.length === 0) {
            return E('p', { 'style': 'color: #666;' }, 'No networks seen yet. Start scanning to see live results.');
        }

        var rows = [
            E('tr', {}, [
                E('th', {}, 'Time'),
                E('th', {}, 'BSSID'),
                E('th', {}, 'SSID'),
                E('th', {}, 'Channel'),
                E('th', {}, 'Signal'),
                E('th', {}, 'Encryption')
            ])
        ];

        networks.forEach(function(net) {
            rows.push(E('tr', {}, [
                E('td', { 'style': 'font-family: monospace; font-size: 0.9em;' }, net.time || ''),
                E('td', { 'style': 'font-family: monospace;' }, net.bssid),
                E('td', {}, net.ssid || '<hidden>'),
                E('td', {}, String(net.channel)),
                E('td', {}, net.signal + ' dBm'),
                E('td', {}, net.encryption)
            ]));
        });

        return E('table', { 'class': 'table', 'style': 'width: 100%;' }, rows);
    },

    renderSessionsTable: function(sessions) {
        if (!sessions || sessions.length === 0) {
            return E('p', { 'style': 'color: #666;' }, 'No previous scans saved yet.');
        }

        var self = this;
        var rows = [
            E('tr', {}, [
                E('th', {}, 'Date/Time'),
                E('th', {}, 'Networks'),
                E('th', {}, 'Actions')
            ])
        ];

        sessions.forEach(function(session) {
            rows.push(E('tr', {}, [
                E('td', {}, session.name || session.id),
                E('td', {}, String(session.networks || 0)),
                E('td', {}, [
                    E('button', {
                        'class': 'cbi-button cbi-button-action',
                        'click': function() { self.handleSessionExport(session.id); },
                        'style': 'margin-right: 5px;'
                    }, 'Download'),
                    E('button', {
                        'class': 'cbi-button cbi-button-remove',
                        'click': function() { self.handleSessionDelete(session.id); }
                    }, 'Delete')
                ])
            ]));
        });

        return E('table', { 'class': 'table', 'style': 'width: 100%;' }, rows);
    },

    pollStatus: function() {
        var self = this;

        return Promise.all([
            callStatus(),
            callGPS(),
            callCurrentScan(state.pageSize),
            callSessions()
        ]).then(function(data) {
            var status = data[0] || {};
            var gps = data[1] || {};
            var currentScan = data[2] || { total: 0, networks: [] };
            var sessions = data[3] || { sessions: [] };

            state.isRunning = status.running;

            var statusEl = document.getElementById('scanner-status');
            var strategyEl = document.getElementById('scanner-strategy');
            var countEl = document.getElementById('network-count');
            var rateEl = document.getElementById('scan-rate');
            var gpsEl = document.getElementById('gps-status');
            var currentScanTotal = document.getElementById('current-scan-total');
            var currentScanContainer = document.getElementById('current-scan-container');
            var sessionsContainer = document.getElementById('sessions-container');

            if (statusEl) statusEl.textContent = status.running ? 'Running' : 'Stopped';
            if (strategyEl) strategyEl.textContent = status.strategy || 'none';
            if (countEl) countEl.textContent = String(status.networks || 0);
            if (rateEl) rateEl.textContent = status.rate || '0/s';
            if (gpsEl) gpsEl.textContent = self.formatGPS(gps);
            if (currentScanTotal) currentScanTotal.textContent = '(' + currentScan.total + ' sightings)';
            if (currentScanContainer) {
                dom.content(currentScanContainer, self.renderCurrentScanTable(currentScan.networks));
            }
            if (sessionsContainer) {
                dom.content(sessionsContainer, self.renderSessionsTable(sessions.sessions));
            }
        });
    },

    handleStart: function() {
        var select = document.getElementById('dwell-select');
        var dwell = parseInt(select.value);

        ui.showModal('Starting...', [E('p', {}, 'Starting scanner with ' + dwell + 'ms dwell')]);

        callStart(dwell).then(function(result) {
            ui.hideModal();
            if (result.success) {
                ui.addNotification(null, E('p', {}, 'Scanner started'), 'success');
            }
        }).catch(function(err) {
            ui.hideModal();
            ui.addNotification(null, E('p', {}, 'Error: ' + err.message), 'error');
        });
    },

    handleStop: function() {
        ui.showModal('Stopping...', [E('p', {}, 'Stopping scanner')]);

        callStop().then(function(result) {
            ui.hideModal();
            if (result.success) {
                ui.addNotification(null, E('p', {}, 'Scanner stopped'), 'success');
            }
        }).catch(function(err) {
            ui.hideModal();
            ui.addNotification(null, E('p', {}, 'Error: ' + err.message), 'error');
        });
    },

    handleExport: function() {
        ui.showModal('Exporting...', [E('p', {}, 'Generating WiGLE CSV export')]);

        callExport().then(function(result) {
            ui.hideModal();
            if (result.success) {
                var link = document.createElement('a');
                link.href = '/cgi-bin/wiglewrt-download?file=' + encodeURIComponent(result.filename);
                link.download = result.filename;
                link.click();
                ui.addNotification(null, E('p', {}, 'Export ready: ' + result.filename), 'success');
            }
        }).catch(function(err) {
            ui.hideModal();
            ui.addNotification(null, E('p', {}, 'Error: ' + err.message), 'error');
        });
    },

    handleSessionExport: function(sessionId) {
        ui.showModal('Exporting...', [E('p', {}, 'Generating WiGLE CSV for session')]);

        callSessionExport(sessionId).then(function(result) {
            ui.hideModal();
            if (result.success) {
                var link = document.createElement('a');
                link.href = '/cgi-bin/wiglewrt-download?file=' + encodeURIComponent(result.filename);
                link.download = result.filename;
                link.click();
                ui.addNotification(null, E('p', {}, 'Export ready: ' + result.filename), 'success');
            }
        }).catch(function(err) {
            ui.hideModal();
            ui.addNotification(null, E('p', {}, 'Error: ' + err.message), 'error');
        });
    },

    handleSessionDelete: function(sessionId) {
        var self = this;

        if (!confirm('Delete session ' + sessionId + '? This cannot be undone.')) {
            return;
        }

        callSessionDelete(sessionId).then(function(result) {
            if (result.success) {
                ui.addNotification(null, E('p', {}, 'Session deleted'), 'success');
                // Refresh sessions list
                callSessions().then(function(sessions) {
                    var container = document.getElementById('sessions-container');
                    if (container) {
                        dom.content(container, self.renderSessionsTable(sessions.sessions));
                    }
                });
            }
        }).catch(function(err) {
            ui.addNotification(null, E('p', {}, 'Error: ' + err.message), 'error');
        });
    },

    handleSaveApply: null,
    handleSave: null,
    handleReset: null
});
