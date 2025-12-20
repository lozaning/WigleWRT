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

var callGetConfig = rpc.declare({
    object: 'wiglewrt',
    method: 'get_config'
});

var callSetConfig = rpc.declare({
    object: 'wiglewrt',
    method: 'set_config',
    params: ['channel_mode', 'channel_offset', 'hop_interval']
});

// State
var state = {
    pageSize: 100,
    currentPage: 0,
    dwell: 500,
    isRunning: false,
    channelMode: 'common',
    channelOffset: '1'
};

return view.extend({
    load: function() {
        return Promise.all([
            callStatus(),
            callGPS(),
            callCurrentScan(state.pageSize),
            callSessions(),
            callGetConfig()
        ]);
    },

    render: function(data) {
        var status = data[0] || {};
        var gps = data[1] || {};
        var currentScan = data[2] || { total: 0, networks: [] };
        var sessions = data[3] || { sessions: [] };
        var config = data[4] || { channel_mode: 'common', channel_offset: '1', hop_interval: 500 };

        state.isRunning = status.running;
        state.channelMode = config.channel_mode || 'common';
        state.channelOffset = config.channel_offset || '1';
        state.dwell = config.hop_interval || 500;

        var view = E('div', { 'class': 'cbi-map' }, [
            E('h2', {}, 'WigleWRT v2.9'),

            // Controls Section
            E('div', { 'class': 'cbi-section' }, [
                E('h3', {}, 'Scanner Controls'),
                E('div', { 'style': 'display: flex; gap: 10px; align-items: center; flex-wrap: wrap; margin-bottom: 1em;' }, [
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

            // Configuration Section
            E('div', { 'class': 'cbi-section' }, [
                E('h3', {}, 'Configuration'),
                E('p', { 'style': 'color: #666; margin-bottom: 1em;' },
                    'Changes take effect on next scanner start.'),
                E('table', { 'class': 'table', 'style': 'width: auto;' }, [
                    E('tr', { 'class': 'tr' }, [
                        E('td', { 'class': 'td', 'style': 'padding-right: 2em; font-weight: bold;' }, 'Dwell Time'),
                        E('td', { 'class': 'td' }, [
                            E('select', { 'id': 'dwell-select', 'class': 'cbi-input-select' }, [
                                E('option', { 'value': '100', 'selected': state.dwell == 100 }, '100ms (fast)'),
                                E('option', { 'value': '500', 'selected': state.dwell == 500 }, '500ms (recommended)'),
                                E('option', { 'value': '1000', 'selected': state.dwell == 1000 }, '1000ms (thorough)')
                            ])
                        ]),
                        E('td', { 'class': 'td', 'style': 'color: #666;' }, 'Time spent on each channel')
                    ]),
                    E('tr', { 'class': 'tr' }, [
                        E('td', { 'class': 'td', 'style': 'padding-right: 2em; font-weight: bold;' }, 'Channel Mode'),
                        E('td', { 'class': 'td' }, [
                            E('select', { 'id': 'channel-mode-select', 'class': 'cbi-input-select' }, [
                                E('option', { 'value': 'common', 'selected': state.channelMode == 'common' }, 'Common Only'),
                                E('option', { 'value': 'all', 'selected': state.channelMode == 'all' }, 'All Channels')
                            ])
                        ]),
                        E('td', { 'class': 'td', 'style': 'color: #666;' }, 'Common: 1,6,11 + main 5GHz. All: includes DFS channels')
                    ]),
                    E('tr', { 'class': 'tr' }, [
                        E('td', { 'class': 'td', 'style': 'padding-right: 2em; font-weight: bold;' }, 'Channel Offset'),
                        E('td', { 'class': 'td' }, [
                            E('select', { 'id': 'channel-offset-select', 'class': 'cbi-input-select' }, [
                                E('option', { 'value': '1', 'selected': state.channelOffset == '1' }, 'Enabled'),
                                E('option', { 'value': '0', 'selected': state.channelOffset == '0' }, 'Disabled')
                            ])
                        ]),
                        E('td', { 'class': 'td', 'style': 'color: #666;' }, 'Offset dual-band radio to avoid channel overlap')
                    ])
                ]),
                E('div', { 'style': 'margin-top: 1em;' }, [
                    E('button', {
                        'class': 'cbi-button cbi-button-save',
                        'click': this.handleSaveConfig.bind(this)
                    }, 'Save Configuration')
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
                        E('td', { 'class': 'td', 'style': 'padding-right: 2em; font-weight: bold;' }, 'Unique Networks'),
                        E('td', { 'class': 'td', 'id': 'unique-count' },
                            String(status.unique_networks || 0))
                    ]),
                    E('tr', { 'class': 'tr' }, [
                        E('td', { 'class': 'td', 'style': 'padding-right: 2em; font-weight: bold;' }, 'Total Sightings'),
                        E('td', { 'class': 'td', 'id': 'sightings-count' },
                            String(status.total_sightings || 0))
                    ]),
                    E('tr', { 'class': 'tr' }, [
                        E('td', { 'class': 'td', 'style': 'padding-right: 2em; font-weight: bold;' }, 'GPS'),
                        E('td', { 'class': 'td', 'id': 'gps-status' },
                            this.formatGPS(gps))
                    ])
                ])
            ]),

            // Current Scan Section
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

    // Get background color based on WiFi band (from channel number)
    // Dark mode compatible colors
    getBandColor: function(channel) {
        var ch = parseInt(channel);
        if (ch >= 1 && ch <= 14) return '#1a3a5c';       // 2.4 GHz - dark blue
        if (ch >= 32 && ch <= 177) return '#1a4a2e';     // 5 GHz - dark green
        if (ch >= 191) return '#3d1a4a';                  // 6 GHz - dark purple
        return 'transparent';
    },

    // Get signal strength color (green/amber/red)
    getSignalColor: function(signal) {
        var sig = parseInt(signal);
        if (sig >= -50) return '#4ade80';  // Strong - green
        if (sig >= -70) return '#fbbf24';  // Medium - amber
        return '#f87171';                   // Weak - red
    },

    // Format coordinates to 6 decimal places
    formatCoord: function(coord) {
        if (!coord || coord === '' || coord === '0') return '-';
        var num = parseFloat(coord);
        return isNaN(num) ? '-' : num.toFixed(6);
    },

    renderCurrentScanTable: function(networks) {
        var self = this;

        // Band color legend
        var legend = E('div', { 'style': 'display: flex; gap: 20px; margin-bottom: 12px; font-size: 14px;' }, [
            E('span', { 'style': 'display: flex; align-items: center; gap: 6px;' }, [
                E('span', { 'style': 'display: inline-block; width: 16px; height: 16px; background: #1a3a5c; border-radius: 3px;' }),
                E('span', { 'style': 'color: #e2e8f0;' }, '2.4 GHz')
            ]),
            E('span', { 'style': 'display: flex; align-items: center; gap: 6px;' }, [
                E('span', { 'style': 'display: inline-block; width: 16px; height: 16px; background: #1a4a2e; border-radius: 3px;' }),
                E('span', { 'style': 'color: #e2e8f0;' }, '5 GHz')
            ]),
            E('span', { 'style': 'display: flex; align-items: center; gap: 6px;' }, [
                E('span', { 'style': 'display: inline-block; width: 16px; height: 16px; background: #3d1a4a; border-radius: 3px;' }),
                E('span', { 'style': 'color: #e2e8f0;' }, '6 GHz')
            ])
        ]);

        if (!networks || networks.length === 0) {
            return E('div', {}, [
                legend,
                E('div', { 'style': 'text-align: center; padding: 40px 20px; color: #e2e8f0; background: rgba(26,26,46,0.3); border-radius: 8px;' }, [
                    E('p', { 'style': 'font-size: 1.2em; margin-bottom: 8px;' }, 'No networks seen yet'),
                    E('p', { 'style': 'font-size: 1em; opacity: 0.7;' }, 'Start scanning to see live results')
                ])
            ]);
        }

        var headerStyle = 'background: #1a1a2e; color: #ffffff; text-transform: uppercase; font-size: 13px; letter-spacing: 0.03em; font-weight: 600;';
        var thStyle = 'padding: 14px 12px; text-align: left; border-bottom: 2px solid #2d2d44;';

        var rows = [
            E('tr', { 'style': headerStyle }, [
                E('th', { 'style': thStyle }, 'Time'),
                E('th', { 'style': thStyle }, 'BSSID'),
                E('th', { 'style': thStyle }, 'SSID'),
                E('th', { 'style': thStyle + ' text-align: center;' }, 'Ch'),
                E('th', { 'style': thStyle + ' text-align: center;' }, 'Signal'),
                E('th', { 'style': thStyle }, 'Lat'),
                E('th', { 'style': thStyle }, 'Lon'),
                E('th', { 'style': thStyle }, 'Encryption'),
                E('th', { 'style': thStyle }, 'Source')
            ])
        ];

        var tdBaseStyle = 'padding: 12px; border-bottom: 1px solid rgba(255,255,255,0.08); color: #ffffff; font-size: 14px;';

        networks.forEach(function(net, idx) {
            var bandColor = self.getBandColor(net.channel);
            var rowOpacity = idx % 2 === 0 ? '1' : '0.9';
            rows.push(E('tr', { 'style': 'background-color: ' + bandColor + '; opacity: ' + rowOpacity + ';' }, [
                E('td', { 'style': tdBaseStyle + ' font-family: monospace; white-space: nowrap;' }, net.time || ''),
                E('td', { 'style': tdBaseStyle + ' font-family: monospace;' }, net.bssid),
                E('td', { 'style': tdBaseStyle + ' max-width: 200px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;' }, net.ssid || E('span', { 'style': 'opacity: 0.6; font-style: italic;' }, 'hidden')),
                E('td', { 'style': tdBaseStyle + ' text-align: center; font-weight: 500;' }, String(net.channel)),
                E('td', { 'style': tdBaseStyle + ' text-align: center; font-weight: 600; color: ' + self.getSignalColor(net.signal) + ';' }, net.signal + ' dBm'),
                E('td', { 'style': tdBaseStyle + ' font-family: monospace;' }, self.formatCoord(net.lat)),
                E('td', { 'style': tdBaseStyle + ' font-family: monospace;' }, self.formatCoord(net.lon)),
                E('td', { 'style': tdBaseStyle }, net.encryption),
                E('td', { 'style': tdBaseStyle }, net.source || 'control')
            ]));
        });

        var table = E('table', { 'class': 'table', 'style': 'width: 100%; border-collapse: separate; border-spacing: 0; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.25);' }, rows);

        return E('div', {}, [legend, table]);
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
            var uniqueEl = document.getElementById('unique-count');
            var sightingsEl = document.getElementById('sightings-count');
            var gpsEl = document.getElementById('gps-status');
            var currentScanTotal = document.getElementById('current-scan-total');
            var currentScanContainer = document.getElementById('current-scan-container');
            var sessionsContainer = document.getElementById('sessions-container');

            if (statusEl) statusEl.textContent = status.running ? 'Running' : 'Stopped';
            if (strategyEl) strategyEl.textContent = status.strategy || 'none';
            if (uniqueEl) uniqueEl.textContent = String(status.unique_networks || 0);
            if (sightingsEl) sightingsEl.textContent = String(status.total_sightings || 0);
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
        var dwellSelect = document.getElementById('dwell-select');
        var dwell = parseInt(dwellSelect.value);

        ui.showModal('Starting...', [E('p', {}, 'Starting scanner with ' + dwell + 'ms dwell')]);

        callStart(dwell).then(function(result) {
            ui.hideModal();
            if (result.success) {
                ui.addNotification(null, E('p', {}, 'Scanner started'), 'success');
            } else {
                ui.addNotification(null, E('p', {}, result.message || 'Failed to start'), 'error');
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

    handleSaveConfig: function() {
        var dwellSelect = document.getElementById('dwell-select');
        var modeSelect = document.getElementById('channel-mode-select');
        var offsetSelect = document.getElementById('channel-offset-select');

        var dwell = parseInt(dwellSelect.value);
        var mode = modeSelect.value;
        var offset = offsetSelect.value;

        ui.showModal('Saving...', [E('p', {}, 'Saving configuration')]);

        callSetConfig(mode, offset, dwell).then(function(result) {
            ui.hideModal();
            if (result.success) {
                ui.addNotification(null, E('p', {}, 'Configuration saved. Restart scanner to apply.'), 'success');
            } else {
                ui.addNotification(null, E('p', {}, result.message || 'Failed to save'), 'error');
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
