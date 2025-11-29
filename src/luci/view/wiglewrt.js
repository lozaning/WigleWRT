'use strict';
'require view';
'require dom';
'require poll';
'require uci';
'require rpc';
'require ui';
'require form';
'require fs';

var callWiglewrtStatus = rpc.declare({
	object: 'wiglewrt',
	method: 'status',
	expect: {}
});

var callWiglewrtNetworks = rpc.declare({
	object: 'wiglewrt',
	method: 'networks',
	params: ['limit', 'offset'],
	expect: {}
});

var callWiglewrtSessions = rpc.declare({
	object: 'wiglewrt',
	method: 'sessions',
	expect: {}
});

var callWiglewrtRadios = rpc.declare({
	object: 'wiglewrt',
	method: 'radios',
	expect: {}
});

var callWiglewrtStart = rpc.declare({
	object: 'wiglewrt',
	method: 'start',
	expect: {}
});

var callWiglewrtStop = rpc.declare({
	object: 'wiglewrt',
	method: 'stop',
	expect: {}
});

var callWiglewrtExport = rpc.declare({
	object: 'wiglewrt',
	method: 'export',
	params: ['session_id'],
	expect: {}
});

var callWiglewrtSessionLog = rpc.declare({
	object: 'wiglewrt',
	method: 'session_log',
	params: ['session_id', 'limit', 'offset', 'filter'],
	expect: {}
});

// Session log state for tabs and pagination
var sessionLogState = {
	activeTab: 'new',   // 'new' or 'all'
	pageSize: 25        // 10, 25, 50, 100
};

// Privacy mode state
var privacyMode = false;

// Helper functions for privacy mode
function maskSSID(ssid) {
	if (!privacyMode || !ssid) return ssid;
	return ssid.replace(/./g, '*');
}

function maskBSSID(bssid) {
	if (!privacyMode || !bssid) return bssid;
	// Show only OUI (first 3 octets), mask the rest
	var parts = bssid.split(':');
	if (parts.length >= 6) {
		return parts[0] + ':' + parts[1] + ':' + parts[2] + ':xx:xx:xx';
	}
	return bssid;
}

function maskCoordinate(coord) {
	if (!privacyMode || !coord || coord === '-') return coord;
	var str = String(coord);
	var dotIndex = str.indexOf('.');
	if (dotIndex === -1) return str;
	// Keep integer part and dot, replace decimal digits with x's
	var intPart = str.substring(0, dotIndex + 1);
	var decPart = str.substring(dotIndex + 1);
	return intPart + decPart.replace(/[0-9]/g, 'x');
}

var callWiglewrtGpsStatus = rpc.declare({
	object: 'wiglewrt',
	method: 'gps_status',
	expect: {}
});

var callWiglewrtVersion = rpc.declare({
	object: 'wiglewrt',
	method: 'version',
	expect: {}
});

var callWiglewrtDeleteSessions = rpc.declare({
	object: 'wiglewrt',
	method: 'delete_sessions',
	params: ['session_ids'],
	expect: {}
});

// Session selection state
var selectedSessions = new Set();

function formatSignal(signal) {
	var sig = parseInt(signal) || -100;
	var quality;
	if (sig >= -50) quality = 'excellent';
	else if (sig >= -60) quality = 'good';
	else if (sig >= -70) quality = 'fair';
	else quality = 'poor';

	return E('span', {
		'class': 'signal-' + quality,
		'style': 'font-weight: bold; color: ' +
			(quality === 'excellent' ? '#22c55e' :
			 quality === 'good' ? '#84cc16' :
			 quality === 'fair' ? '#eab308' : '#ef4444')
	}, signal + ' dBm');
}

function formatEncryption(enc) {
	var color = enc.includes('WPA') ? '#22c55e' :
	            enc.includes('WEP') ? '#eab308' : '#ef4444';
	return E('span', {'style': 'color: ' + color}, enc);
}

function formatTimeAgo(timestamp) {
	if (!timestamp) return '-';
	var now = new Date();
	var then = new Date(timestamp.replace(' ', 'T'));
	var diff = Math.floor((now - then) / 1000);

	if (diff < 60) return diff + 's ago';
	if (diff < 3600) return Math.floor(diff / 60) + 'm ago';
	if (diff < 86400) return Math.floor(diff / 3600) + 'h ago';
	return Math.floor(diff / 86400) + 'd ago';
}

return view.extend({
	currentSessionId: null,

	load: function() {
		var self = this;
		return Promise.all([
			callWiglewrtStatus(),
			callWiglewrtNetworks(100, 0),
			callWiglewrtSessions(),
			callWiglewrtRadios(),
			callWiglewrtGpsStatus(),
			uci.load('wiglewrt'),
			callWiglewrtVersion()
		]).then(function(results) {
			// Store current session for session log loading
			self.currentSessionId = results[0].current_session || null;
			// Load session log if we have a current session
			if (self.currentSessionId) {
				var filter = sessionLogState.activeTab === 'new' ? 'new' : 'all';
				return callWiglewrtSessionLog(self.currentSessionId, sessionLogState.pageSize, 0, filter).then(function(logData) {
					results.push(logData);
					return results;
				});
			}
			results.push({ entries: [] });
			return results;
		});
	},

	renderStatus: function(status, gpsStatus) {
		var gps = gpsStatus || {};
		var gpsText, gpsColor;
		var satsCount = gps.sats !== undefined ? gps.sats : 0;
		var satsText = ' (' + satsCount + ' sats)';
		if (!gps.available) {
			gpsText = '✗ No GPS device';
			gpsColor = '#ef4444';
		} else if (!gps.fix) {
			gpsText = '○ Searching' + satsText;
			gpsColor = '#eab308';
		} else {
			gpsText = '● Fix' + satsText + ': ' + maskCoordinate(gps.lat) + ', ' + maskCoordinate(gps.lon);
			gpsColor = '#22c55e';
		}

		var statusBox = E('div', {'class': 'cbi-section'}, [
			E('h3', {}, 'Scanner Status'),
			E('div', {'style': 'display: flex; gap: 40px; flex-wrap: wrap'}, [
				E('div', {'class': 'table', 'style': 'flex: 1; min-width: 280px'}, [
					E('div', {'class': 'tr'}, [
						E('div', {'class': 'td', 'style': 'width: 120px; font-weight: bold'}, 'Status'),
						E('div', {'class': 'td', 'id': 'scanner-status'},
							status.running ?
								E('span', {'style': 'color: #22c55e; font-weight: bold'}, '● Running') :
								E('span', {'style': 'color: #6b7280'}, '○ Stopped')
						)
					]),
					E('div', {'class': 'tr'}, [
						E('div', {'class': 'td', 'style': 'font-weight: bold'}, 'GPS'),
						E('div', {'class': 'td', 'id': 'gps-status'},
							E('span', {'style': 'color: ' + gpsColor}, gpsText)
						)
					]),
					E('div', {'class': 'tr'}, [
						E('div', {'class': 'td', 'style': 'font-weight: bold'}, 'Session'),
						E('div', {'class': 'td', 'id': 'current-session'},
							status.current_session || '-'
						)
					])
				]),
				E('div', {'class': 'table', 'style': 'flex: 1; min-width: 280px'}, [
					E('div', {'class': 'tr'}, [
						E('div', {'class': 'td', 'style': 'width: 120px; font-weight: bold'}, 'Total Networks'),
						E('div', {'class': 'td', 'id': 'total-networks'},
							status.total_networks || 0
						)
					]),
					E('div', {'class': 'tr'}, [
						E('div', {'class': 'td', 'style': 'font-weight: bold'}, 'Started'),
						E('div', {'class': 'td', 'id': 'session-start'},
							status.session_start || '-'
						)
					]),
					E('div', {'class': 'tr'}, [
						E('div', {'class': 'td', 'style': 'font-weight: bold'}, 'New This Session'),
						E('div', {'class': 'td', 'id': 'session-new', 'style': 'color: #22c55e; font-weight: bold'},
							status.session_new || '0'
						)
					])
				])
			])
		]);

		return statusBox;
	},

	renderRadioInfo: function() {
		// Get hop interval from UCI
		var hopInterval = uci.get('wiglewrt', 'settings', 'hop_interval') || '500';

		// Build radio rows
		var radioRows = [];
		var radios = [
			{ id: 'radio0', name: 'phy0', band: '2.4 GHz' },
			{ id: 'radio1', name: 'phy1', band: '5 GHz' },
			{ id: 'radio2', name: 'phy2', band: 'Dual-band' }
		];

		radios.forEach(function(radio) {
			var enabled = uci.get('wiglewrt', radio.id, 'enabled') === '1';
			var channels = uci.get('wiglewrt', radio.id, 'channels');
			var band = radio.band;

			// For radio2, check actual band setting
			if (radio.id === 'radio2') {
				var configBand = uci.get('wiglewrt', radio.id, 'band');
				if (configBand === '5g') {
					band = '5 GHz (dual)';
				} else {
					band = '2.4 GHz (dual)';
				}
			}

			// Format channels array
			var channelStr = '-';
			if (channels) {
				if (Array.isArray(channels)) {
					channelStr = channels.join(', ');
				} else {
					channelStr = String(channels);
				}
			}

			var statusSpan = enabled ?
				E('span', {'style': 'color: #22c55e'}, '● Active') :
				E('span', {'style': 'color: #6b7280'}, '○ Disabled');

			radioRows.push(E('div', {'class': 'tr'}, [
				E('div', {'class': 'td', 'style': 'width: 60px; font-weight: bold'}, radio.name),
				E('div', {'class': 'td', 'style': 'width: 100px'}, band),
				E('div', {'class': 'td', 'style': 'width: 80px'}, statusSpan),
				E('div', {'class': 'td', 'style': 'font-family: monospace; font-size: 12px'}, channelStr)
			]));
		});

		return E('div', {'style': 'margin-top: 15px; padding: 10px; border-radius: 4px; border: 1px solid rgba(255,255,255,0.1); background: rgba(255,255,255,0.05)'}, [
			E('div', {'style': 'display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px'}, [
				E('strong', {'style': 'font-size: 13px'}, 'Radio Configuration'),
				E('span', {'style': 'font-size: 12px; color: #6b7280'},
					'Hop interval: ' + hopInterval + 'ms')
			]),
			E('div', {'class': 'table', 'style': 'font-size: 12px'}, [
				E('div', {'class': 'tr table-titles'}, [
					E('div', {'class': 'th', 'style': 'width: 60px'}, 'Radio'),
					E('div', {'class': 'th', 'style': 'width: 100px'}, 'Band'),
					E('div', {'class': 'th', 'style': 'width: 80px'}, 'Status'),
					E('div', {'class': 'th'}, 'Hopping Channels')
				])
			].concat(radioRows))
		]);
	},

	renderControls: function(status) {
		var self = this;
		var isRunning = (status.running == 1 || status.running === true);

		var startBtn = E('button', {
			'class': 'cbi-button cbi-button-apply'
		}, 'Start Scanning');

		if (isRunning) {
			startBtn.setAttribute('disabled', '');
		}

		startBtn.addEventListener('click', function() {
			if (this.disabled) return;
			this.setAttribute('disabled', '');
			callWiglewrtStart().then(function(res) {
				ui.addNotification(null, E('p', res.message || 'Starting...'));
				window.setTimeout(function() { location.reload() }, 1500);
			}).catch(function(err) {
				ui.addNotification(null, E('p', 'Error: ' + err.message), 'error');
				startBtn.removeAttribute('disabled');
			});
		});

		var stopBtn = E('button', {
			'class': 'cbi-button cbi-button-reset',
			'style': 'margin-left: 10px'
		}, 'Stop Scanning');

		if (!isRunning) {
			stopBtn.setAttribute('disabled', '');
		}

		stopBtn.addEventListener('click', function() {
			if (this.disabled) return;
			this.setAttribute('disabled', '');
			callWiglewrtStop().then(function(res) {
				ui.addNotification(null, E('p', res.message || 'Stopping...'));
				window.setTimeout(function() { location.reload() }, 1500);
			}).catch(function(err) {
				ui.addNotification(null, E('p', 'Error: ' + err.message), 'error');
				stopBtn.removeAttribute('disabled');
			});
		});

		var exportBtn = E('button', {
			'class': 'cbi-button',
			'style': 'margin-left: 10px'
		}, 'Export All (WiGLE CSV)');

		exportBtn.addEventListener('click', function() {
			callWiglewrtExport('').then(function(res) {
				if (res.success && res.filepath) {
					ui.addNotification(null, E('p', 'Exported to: ' + res.filepath));
					// Trigger download via CGI handler
					var link = document.createElement('a');
					link.href = '/cgi-bin/wiglewrt-download?file=' +
						encodeURIComponent(res.filepath);
					link.download = res.filepath.split('/').pop();
					document.body.appendChild(link);
					link.click();
					document.body.removeChild(link);
				} else {
					ui.addNotification(null, E('p', 'Export failed'), 'error');
				}
			}).catch(function(err) {
				ui.addNotification(null, E('p', 'Export error: ' + err.message), 'error');
			});
		});

		var privacyBtn = E('button', {
			'id': 'privacy-mode-btn',
			'class': 'cbi-button',
			'style': 'margin-left: 20px; ' + (privacyMode ? 'background: #7c3aed; color: white;' : '')
		}, privacyMode ? '🔒 Privacy Mode ON' : '🔓 Privacy Mode');

		privacyBtn.addEventListener('click', function() {
			privacyMode = !privacyMode;
			this.textContent = privacyMode ? '🔒 Privacy Mode ON' : '🔓 Privacy Mode';
			this.style.cssText = 'margin-left: 20px; ' + (privacyMode ? 'background: #7c3aed; color: white;' : '');
			// Force refresh of the session log table
			var table = document.getElementById('session-log-table');
			if (table) {
				// Trigger a re-render by updating existing rows
				var rows = table.querySelectorAll('.tr:not(.table-titles)');
				rows.forEach(function(row) {
					var cells = row.querySelectorAll('.td');
					if (cells.length >= 7) {
						// BSSID is in cell 1, SSID is in cell 2, lat is cell 5, lon is cell 6
						var bssidCell = cells[1];
						var ssidCell = cells[2];
						var latCell = cells[5];
						var lonCell = cells[6];
						var bssid = bssidCell.getAttribute('data-bssid') || bssidCell.textContent;
						var ssid = ssidCell.getAttribute('data-ssid') || ssidCell.textContent;
						var lat = latCell.getAttribute('data-lat') || latCell.textContent;
						var lon = lonCell.getAttribute('data-lon') || lonCell.textContent;

						// Store original values if not already stored
						if (!bssidCell.getAttribute('data-bssid')) {
							bssidCell.setAttribute('data-bssid', bssid);
						}
						if (!ssidCell.getAttribute('data-ssid')) {
							ssidCell.setAttribute('data-ssid', ssid);
						}
						if (!latCell.getAttribute('data-lat')) {
							latCell.setAttribute('data-lat', lat);
						}
						if (!lonCell.getAttribute('data-lon')) {
							lonCell.setAttribute('data-lon', lon);
						}

						// Apply or remove masking
						bssidCell.textContent = maskBSSID(bssidCell.getAttribute('data-bssid'));
						ssidCell.textContent = maskSSID(ssidCell.getAttribute('data-ssid'));
						latCell.textContent = maskCoordinate(latCell.getAttribute('data-lat'));
						lonCell.textContent = maskCoordinate(lonCell.getAttribute('data-lon'));
					}
				});
			}
			// Update GPS status display
			var gpsEl = document.getElementById('gps-status');
			if (gpsEl) {
				var gpsSpan = gpsEl.querySelector('span');
				if (gpsSpan) {
					var text = gpsSpan.textContent;
					// Check if it contains coordinates (has "Fix" and ":")
					if (text.indexOf('Fix') !== -1 && text.indexOf(':') !== -1) {
						var parts = text.split(': ');
						if (parts.length === 2) {
							var coords = parts[1].split(', ');
							if (coords.length === 2) {
								// Store original if not stored
								if (!gpsSpan.getAttribute('data-lat')) {
									gpsSpan.setAttribute('data-lat', coords[0]);
									gpsSpan.setAttribute('data-lon', coords[1]);
								}
								var lat = gpsSpan.getAttribute('data-lat');
								var lon = gpsSpan.getAttribute('data-lon');
								gpsSpan.textContent = parts[0] + ': ' + maskCoordinate(lat) + ', ' + maskCoordinate(lon);
							}
						}
					}
				}
			}
		});

		return E('div', {'class': 'cbi-section'}, [
			E('h3', {}, 'Controls'),
			E('div', {'style': 'margin: 10px 0'}, [startBtn, stopBtn, exportBtn, privacyBtn]),
			this.renderRadioInfo()
		]);
	},

	renderSessionLog: function(sessionLog, sessionId) {
		var self = this;
		var entries = (sessionLog.entries || []).filter(function(entry) {
			return entry.bssid && entry.bssid.length > 0;
		});
		var unique = sessionLog.unique || 0;
		var newCount = sessionLog.new_networks || 0;
		var filteredTotal = sessionLog.filtered_total || entries.length;

		var rows = entries.map(function(entry) {
			var newIndicator = entry.is_new ?
				E('span', {'style': 'color: #3b82f6; font-weight: bold'}, '★') :
				E('span', {'style': 'color: #d1d5db'}, '○');

			var latDisplay = entry.lat && entry.lat !== '' ?
				parseFloat(entry.lat).toFixed(5) : '-';
			var lonDisplay = entry.lon && entry.lon !== '' ?
				parseFloat(entry.lon).toFixed(5) : '-';

			var ssidDisplay = entry.ssid || '<hidden>';

			return E('div', {'class': 'tr' + (entry.is_new ? ' new-network' : '')}, [
				E('div', {'class': 'td', 'style': 'text-align: center'}, newIndicator),
				E('div', {'class': 'td', 'style': 'font-family: monospace; font-size: 11px', 'data-bssid': entry.bssid}, maskBSSID(entry.bssid)),
				E('div', {'class': 'td', 'data-ssid': ssidDisplay}, maskSSID(ssidDisplay)),
				E('div', {'class': 'td', 'style': 'text-align: center'}, entry.channel),
				E('div', {'class': 'td', 'style': 'text-align: center'}, formatSignal(entry.signal)),
				E('div', {'class': 'td', 'style': 'font-family: monospace; font-size: 10px', 'data-lat': latDisplay}, maskCoordinate(latDisplay)),
				E('div', {'class': 'td', 'style': 'font-family: monospace; font-size: 10px', 'data-lon': lonDisplay}, maskCoordinate(lonDisplay)),
				E('div', {'class': 'td', 'style': 'font-size: 11px'}, entry.timestamp || '-')
			]);
		});

		if (rows.length === 0) {
			rows.push(E('div', {'class': 'tr placeholder'}, [
				E('div', {'class': 'td', 'style': 'text-align: center; color: #6b7280; grid-column: span 8'},
					sessionId ? 'No networks in this view yet.' : 'No active session. Start scanning to see networks.')
			]));
		}

		// Tab button styles
		var activeTabStyle = 'padding: 8px 16px; border: none; background: #2563eb; color: white; cursor: pointer; border-radius: 4px 4px 0 0; font-weight: bold;';
		var inactiveTabStyle = 'padding: 8px 16px; border: none; background: #e5e7eb; color: #374151; cursor: pointer; border-radius: 4px 4px 0 0;';

		var newTabBtn = E('button', {
			'id': 'tab-new',
			'style': sessionLogState.activeTab === 'new' ? activeTabStyle : inactiveTabStyle,
			'click': function() {
				sessionLogState.activeTab = 'new';
				// Trigger immediate refresh
				document.getElementById('tab-new').style.cssText = activeTabStyle;
				document.getElementById('tab-all').style.cssText = inactiveTabStyle;
			}
		}, 'New Networks (' + newCount + ')');

		var allTabBtn = E('button', {
			'id': 'tab-all',
			'style': sessionLogState.activeTab === 'all' ? activeTabStyle : inactiveTabStyle,
			'click': function() {
				sessionLogState.activeTab = 'all';
				document.getElementById('tab-all').style.cssText = activeTabStyle;
				document.getElementById('tab-new').style.cssText = inactiveTabStyle;
			}
		}, 'All Sightings (' + (sessionLog.total || 0) + ')');

		// Page size dropdown
		var pageSizeSelect = E('select', {
			'id': 'page-size-select',
			'style': 'padding: 6px 10px; border: 1px solid #d1d5db; border-radius: 4px; margin-left: auto;',
			'change': function(ev) {
				sessionLogState.pageSize = parseInt(ev.target.value);
			}
		}, [
			E('option', { 'value': '10', 'selected': sessionLogState.pageSize === 10 }, 'Show 10'),
			E('option', { 'value': '25', 'selected': sessionLogState.pageSize === 25 }, 'Show 25'),
			E('option', { 'value': '50', 'selected': sessionLogState.pageSize === 50 }, 'Show 50'),
			E('option', { 'value': '100', 'selected': sessionLogState.pageSize === 100 }, 'Show 100')
		]);

		var tabBar = E('div', {'style': 'display: flex; align-items: center; gap: 4px; margin-bottom: 0; border-bottom: 2px solid #2563eb; padding-bottom: 0;'}, [
			newTabBtn,
			allTabBtn,
			E('div', {'style': 'flex-grow: 1'}),
			E('span', {'style': 'font-size: 12px; color: #6b7280; margin-right: 8px'},
				'Showing ' + entries.length + ' of ' + filteredTotal),
			pageSizeSelect
		]);

		return E('div', {'class': 'cbi-section'}, [
			E('h3', {'id': 'session-activity-header'}, 'Session Activity'),
			tabBar,
			E('div', {'class': 'table', 'id': 'session-log-table', 'style': 'font-size: 13px; margin-top: 0;'}, [
				E('div', {'class': 'tr table-titles'}, [
					E('div', {'class': 'th', 'style': 'text-align: center; width: 40px'}, 'New'),
					E('div', {'class': 'th'}, 'BSSID'),
					E('div', {'class': 'th'}, 'SSID'),
					E('div', {'class': 'th', 'style': 'text-align: center; width: 40px'}, 'Ch'),
					E('div', {'class': 'th', 'style': 'text-align: center; width: 80px'}, 'Signal'),
					E('div', {'class': 'th', 'style': 'width: 90px'}, 'Latitude'),
					E('div', {'class': 'th', 'style': 'width: 90px'}, 'Longitude'),
					E('div', {'class': 'th'}, 'Time')
				])
			].concat(rows))
		]);
	},

	renderSessions: function(sessionsData) {
		var sessions = sessionsData.sessions || [];

		// Clear selection state on render (fresh data)
		selectedSessions.clear();

		// Helper to update delete button state
		function updateDeleteButtonState() {
			var deleteBtn = document.getElementById('delete-selected-btn');
			var countSpan = document.getElementById('selected-count');
			if (deleteBtn) {
				if (selectedSessions.size > 0) {
					deleteBtn.removeAttribute('disabled');
					deleteBtn.textContent = 'Delete Selected (' + selectedSessions.size + ')';
				} else {
					deleteBtn.setAttribute('disabled', '');
					deleteBtn.textContent = 'Delete Selected';
				}
			}
			if (countSpan) {
				countSpan.textContent = selectedSessions.size > 0 ? selectedSessions.size + ' selected' : '';
			}
		}

		// Helper to update select-all checkbox state
		function updateSelectAllState() {
			var selectAllCb = document.getElementById('select-all-sessions');
			if (selectAllCb && sessions.length > 0) {
				selectAllCb.checked = selectedSessions.size === sessions.length;
				selectAllCb.indeterminate = selectedSessions.size > 0 && selectedSessions.size < sessions.length;
			}
		}

		var rows = sessions.map(function(sess) {
			var checkbox = E('input', {
				'type': 'checkbox',
				'class': 'session-checkbox',
				'data-session': sess.session_id,
				'style': 'cursor: pointer; width: 16px; height: 16px;'
			});

			checkbox.addEventListener('change', function() {
				var sid = this.getAttribute('data-session');
				if (this.checked) {
					selectedSessions.add(sid);
				} else {
					selectedSessions.delete(sid);
				}
				updateDeleteButtonState();
				updateSelectAllState();
			});

			var exportBtn = E('button', {
				'class': 'cbi-button cbi-button-action',
				'style': 'padding: 2px 8px; font-size: 12px',
				'data-session': sess.session_id
			}, 'Export');

			exportBtn.addEventListener('click', function() {
				var sid = this.getAttribute('data-session');
				callWiglewrtExport(sid).then(function(res) {
					if (res.success && res.filepath) {
						ui.addNotification(null, E('p', 'Exported session to: ' + res.filepath));
						// Trigger download via CGI handler
						var link = document.createElement('a');
						link.href = '/cgi-bin/wiglewrt-download?file=' +
							encodeURIComponent(res.filepath);
						link.download = res.filepath.split('/').pop();
						document.body.appendChild(link);
						link.click();
						document.body.removeChild(link);
					} else {
						ui.addNotification(null, E('p', 'Export failed'), 'error');
					}
				}).catch(function(err) {
					ui.addNotification(null, E('p', 'Export error: ' + err.message), 'error');
				});
			});

			return E('tr', {'class': 'tr'}, [
				E('td', {'class': 'td', 'style': 'text-align: center; width: 40px'}, checkbox),
				E('td', {'class': 'td'}, sess.session_id),
				E('td', {'class': 'td'}, sess.start_time || '-'),
				E('td', {'class': 'td'}, sess.end_time || 'Running'),
				E('td', {'class': 'td', 'style': 'text-align: center; font-weight: bold; color: #22c55e'},
					sess.new_networks || 0),
				E('td', {'class': 'td', 'style': 'text-align: center'}, sess.networks_at_end || '-'),
				E('td', {'class': 'td', 'style': 'text-align: center'},
					sess.status === 'running' ?
						E('span', {'style': 'color: #22c55e'}, '● Running') :
						E('span', {'style': 'color: #6b7280'}, 'Completed')
				),
				E('td', {'class': 'td'}, exportBtn)
			]);
		});

		if (rows.length === 0) {
			rows.push(E('tr', {'class': 'tr placeholder'}, [
				E('td', {'class': 'td', 'colspan': 8, 'style': 'text-align: center; color: #6b7280'},
					'No scan sessions yet.')
			]));
		}

		// Select All checkbox for header
		var selectAllCheckbox = E('input', {
			'type': 'checkbox',
			'id': 'select-all-sessions',
			'style': 'cursor: pointer; width: 16px; height: 16px;'
		});

		selectAllCheckbox.addEventListener('change', function() {
			var checked = this.checked;
			var checkboxes = document.querySelectorAll('.session-checkbox');
			checkboxes.forEach(function(cb) {
				cb.checked = checked;
				var sid = cb.getAttribute('data-session');
				if (checked) {
					selectedSessions.add(sid);
				} else {
					selectedSessions.delete(sid);
				}
			});
			updateDeleteButtonState();
		});

		// Delete button
		var deleteBtn = E('button', {
			'id': 'delete-selected-btn',
			'class': 'cbi-button cbi-button-negative',
			'style': 'margin-left: 10px',
			'disabled': ''
		}, 'Delete Selected');

		deleteBtn.addEventListener('click', function() {
			if (selectedSessions.size === 0) return;

			var count = selectedSessions.size;
			var sessionWord = count === 1 ? 'session' : 'sessions';

			ui.showModal('Delete Sessions', [
				E('p', {}, 'Are you sure you want to delete ' + count + ' ' + sessionWord + '?'),
				E('p', {'style': 'color: #ef4444; font-weight: bold'}, 'This action cannot be undone.'),
				E('div', {'class': 'right'}, [
					E('button', {
						'class': 'cbi-button',
						'click': ui.hideModal
					}, 'Cancel'),
					E('button', {
						'class': 'cbi-button cbi-button-negative',
						'style': 'margin-left: 10px',
						'click': function() {
							var sessionIds = Array.from(selectedSessions);
							ui.hideModal();

							callWiglewrtDeleteSessions(sessionIds).then(function(res) {
								if (res.success) {
									ui.addNotification(null,
										E('p', 'Deleted ' + res.deleted + ' session(s)'));
									selectedSessions.clear();
									window.setTimeout(function() { location.reload(); }, 1000);
								} else {
									ui.addNotification(null,
										E('p', 'Delete failed'), 'error');
								}
							}).catch(function(err) {
								ui.addNotification(null,
									E('p', 'Delete error: ' + err.message), 'error');
							});
						}
					}, 'Delete')
				])
			]);
		});

		// Control bar with select all and delete button
		var controlBar = E('div', {
			'style': 'display: flex; align-items: center; gap: 10px; margin-bottom: 10px; padding: 8px; border-radius: 4px; border: 1px solid rgba(255,255,255,0.1); background: rgba(255,255,255,0.05)'
		}, [
			E('label', {'style': 'display: flex; align-items: center; gap: 6px; cursor: pointer;'}, [
				selectAllCheckbox,
				E('span', {}, 'Select All')
			]),
			deleteBtn,
			E('span', {'id': 'selected-count', 'style': 'color: #6b7280; font-size: 12px; margin-left: auto'}, '')
		]);

		return E('div', {'class': 'cbi-section'}, [
			E('h3', {}, 'Scan Sessions'),
			controlBar,
			E('div', {'class': 'table'}, [
				E('div', {'class': 'tr table-titles'}, [
					E('div', {'class': 'th', 'style': 'text-align: center; width: 40px'}, ''),
					E('div', {'class': 'th'}, 'Session ID'),
					E('div', {'class': 'th'}, 'Started'),
					E('div', {'class': 'th'}, 'Ended'),
					E('div', {'class': 'th', 'style': 'text-align: center'}, 'New'),
					E('div', {'class': 'th', 'style': 'text-align: center'}, 'Total'),
					E('div', {'class': 'th', 'style': 'text-align: center'}, 'Status'),
					E('div', {'class': 'th'}, 'Export')
				])
			].concat(rows))
		]);
	},

	renderConfig: function(radios) {
		var m, s, o;

		m = new form.Map('wiglewrt', 'WigleWRT Configuration',
			'Configure the WiFi scanner settings and channel hopping.');

		// Main settings
		s = m.section(form.NamedSection, 'settings', 'wiglewrt', 'General Settings');

		o = s.option(form.Flag, 'enabled', 'Enable Scanner',
			'Enable or disable the WiFi scanner service');
		o.rmempty = false;

		o = s.option(form.Flag, 'autostart', 'Auto-start on Boot',
			'Automatically start scanning when the device boots');
		o.rmempty = false;

		o = s.option(form.Value, 'scan_interval', 'Scan Interval (seconds)',
			'Time between scan cycles');
		o.datatype = 'uinteger';
		o.default = '2';

		// Radio 0 (2.4GHz)
		s = m.section(form.NamedSection, 'radio0', 'radio', 'Radio 0 (2.4GHz)');

		o = s.option(form.Flag, 'enabled', 'Enable this radio for scanning');
		o.default = '1';

		o = s.option(form.MultiValue, 'channels', 'Channels to scan');
		for (var i = 1; i <= 14; i++) {
			o.value(String(i), 'Channel ' + i);
		}
		o.default = '1 6 11';

		// Radio 1 (5GHz)
		s = m.section(form.NamedSection, 'radio1', 'radio', 'Radio 1 (5GHz)');

		o = s.option(form.Flag, 'enabled', 'Enable this radio for scanning');
		o.default = '1';

		o = s.option(form.MultiValue, 'channels', 'Channels to scan');
		var channels5g = [36, 40, 44, 48, 52, 56, 60, 64, 100, 104, 108, 112,
		                  116, 120, 124, 128, 132, 136, 140, 144, 149, 153, 157, 161, 165];
		channels5g.forEach(function(ch) {
			o.value(String(ch), 'Channel ' + ch);
		});
		o.default = '36 40 44 48 149 153 157 161 165';

		// Radio 2 (dual-band)
		s = m.section(form.NamedSection, 'radio2', 'radio', 'Radio 2 (Dual-band)');

		o = s.option(form.Flag, 'enabled', 'Enable this radio for scanning');
		o.default = '1';

		o = s.option(form.ListValue, 'band', 'Operating Band');
		o.value('2g', '2.4 GHz');
		o.value('5g', '5 GHz');
		o.default = '2g';

		o = s.option(form.MultiValue, 'channels', 'Channels to scan',
			'Select channels appropriate for the chosen band');
		for (var i = 1; i <= 14; i++) {
			o.value(String(i), '2.4GHz Ch ' + i);
		}
		channels5g.forEach(function(ch) {
			o.value(String(ch), '5GHz Ch ' + ch);
		});
		o.default = '1 6 11';

		return m.render();
	},

	render: function(data) {
		var status = data[0] || {};
		var networks = data[1] || {};
		var sessions = data[2] || {};
		var radios = data[3] || {};
		var gpsStatus = data[4] || {};
		var versionInfo = data[6] || {};
		var sessionLog = data[7] || { entries: [] };
		var version = versionInfo.version || '2.1.0';

		var self = this;
		var currentSessionId = status.current_session || null;

		// Setup polling for auto-refresh
		poll.add(function() {
			// Use current tab and page size from state
			var filter = sessionLogState.activeTab === 'new' ? 'new' : 'all';
			var limit = sessionLogState.pageSize;

			return Promise.all([
				callWiglewrtStatus(),
				callWiglewrtGpsStatus(),
				currentSessionId ? callWiglewrtSessionLog(currentSessionId, limit, 0, filter) : Promise.resolve({ entries: [] })
			]).then(function(results) {
				var newStatus = results[0];
				var newGps = results[1];
				var newLog = results[2];

				// Update scanner status
				var statusEl = document.getElementById('scanner-status');
				if (statusEl) {
					statusEl.innerHTML = '';
					statusEl.appendChild(
						newStatus.running ?
							E('span', {'style': 'color: #22c55e; font-weight: bold'}, '● Running') :
							E('span', {'style': 'color: #6b7280'}, '○ Stopped')
					);
				}

				// Update GPS status
				var gpsEl = document.getElementById('gps-status');
				if (gpsEl) {
					var gpsText, gpsColor;
					var satsCount = newGps.sats !== undefined ? newGps.sats : 0;
					var satsText = ' (' + satsCount + ' sats)';
					if (!newGps.available) {
						gpsText = '✗ No GPS device';
						gpsColor = '#ef4444';
					} else if (!newGps.fix) {
						gpsText = '○ Searching' + satsText;
						gpsColor = '#eab308';
					} else {
						gpsText = '● Fix' + satsText + ': ' + maskCoordinate(newGps.lat) + ', ' + maskCoordinate(newGps.lon);
						gpsColor = '#22c55e';
					}
					gpsEl.innerHTML = '';
					gpsEl.appendChild(E('span', {'style': 'color: ' + gpsColor}, gpsText));
				}

				// Update stats
				var totalEl = document.getElementById('total-networks');
				if (totalEl) totalEl.textContent = newStatus.total_networks || 0;

				var sessionEl = document.getElementById('current-session');
				if (sessionEl) sessionEl.textContent = newStatus.current_session || '-';

				var startEl = document.getElementById('session-start');
				if (startEl) startEl.textContent = newStatus.session_start || '-';

				var newEl = document.getElementById('session-new');
				if (newEl) newEl.textContent = newStatus.session_new || '0';

				// Update session log table, tabs, and counts
				if (newLog) {
					// Update tab labels with counts
					var newTabEl = document.getElementById('tab-new');
					var allTabEl = document.getElementById('tab-all');
					if (newTabEl) newTabEl.textContent = 'New Networks (' + (newLog.new_networks || 0) + ')';
					if (allTabEl) allTabEl.textContent = 'All Sightings (' + (newLog.total || 0) + ')';

					var table = document.getElementById('session-log-table');
					if (table && newLog.entries) {
						// Keep header, replace rows
						while (table.children.length > 1) {
							table.removeChild(table.lastChild);
						}
						var entries = newLog.entries.filter(function(e) {
							return e.bssid && e.bssid.length > 0;
						});

						if (entries.length === 0) {
							table.appendChild(E('div', {'class': 'tr placeholder'}, [
								E('div', {'class': 'td', 'style': 'text-align: center; color: #6b7280; grid-column: span 8'},
									'No networks in this view yet.')
							]));
						} else {
							entries.forEach(function(entry) {
								var newIndicator = entry.is_new ?
									E('span', {'style': 'color: #3b82f6; font-weight: bold'}, '★') :
									E('span', {'style': 'color: #d1d5db'}, '○');
								var latDisplay = entry.lat && entry.lat !== '' ?
									parseFloat(entry.lat).toFixed(5) : '-';
								var lonDisplay = entry.lon && entry.lon !== '' ?
									parseFloat(entry.lon).toFixed(5) : '-';
								var ssidDisplay = entry.ssid || '<hidden>';

								table.appendChild(E('div', {'class': 'tr' + (entry.is_new ? ' new-network' : '')}, [
									E('div', {'class': 'td', 'style': 'text-align: center'}, newIndicator),
									E('div', {'class': 'td', 'style': 'font-family: monospace; font-size: 11px', 'data-bssid': entry.bssid}, maskBSSID(entry.bssid)),
									E('div', {'class': 'td', 'data-ssid': ssidDisplay}, maskSSID(ssidDisplay)),
									E('div', {'class': 'td', 'style': 'text-align: center'}, entry.channel),
									E('div', {'class': 'td', 'style': 'text-align: center'}, formatSignal(entry.signal)),
									E('div', {'class': 'td', 'style': 'font-family: monospace; font-size: 10px', 'data-lat': latDisplay}, maskCoordinate(latDisplay)),
									E('div', {'class': 'td', 'style': 'font-family: monospace; font-size: 10px', 'data-lon': lonDisplay}, maskCoordinate(lonDisplay)),
									E('div', {'class': 'td', 'style': 'font-size: 11px'}, entry.timestamp || '-')
								]));
							});
						}
					}
				}

				// Update current session ID if changed
				if (newStatus.current_session !== currentSessionId) {
					currentSessionId = newStatus.current_session;
				}
			});
		}, 3);

		return E('div', {'class': 'cbi-map'}, [
			E('h2', {}, 'WigleWRT - WiFi Scanner v' + version),
			E('div', {'class': 'cbi-map-descr'},
				'Scan for WiFi networks using all available radios with channel hopping. ' +
				'Export results in WiGLE CSV format for wardriving.'),
			this.renderStatus(status, gpsStatus),
			this.renderControls(status),
			this.renderSessionLog(sessionLog, currentSessionId),
			this.renderSessions(sessions),
			E('div', {'id': 'config-section'}),
			this.renderConfig(radios)
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
