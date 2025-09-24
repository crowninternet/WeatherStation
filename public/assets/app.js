// Utility functions
async function fetchJSON(url, opts = {}) {
    try {
        // cache buster + no-store by default
        const noCache = opts.noCache !== false;
        const sep = url.includes('?') ? '&' : '?';
        const cacheBusted = noCache ? `${url}${sep}_ts=${Date.now()}` : url;
        const response = await fetch(cacheBusted, {
            cache: 'no-store',
            headers: { 'Cache-Control': 'no-cache' },
        });
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }
        return await response.json();
    } catch (error) {
        console.error('Fetch error:', error);
        throw error;
    }
}

function formatTimestamp(isoString) {
    const date = new Date(isoString);
    return date.toLocaleString('en-US', {
        timeZone: 'America/Phoenix',
        year: 'numeric',
        month: 'short',
        day: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
        hour12: true
    });
}

function formatValue(value, unit = '') {
    if (value === null || value === undefined) return 'N/A';
    return `${Number(value).toFixed(1)}${unit}`;
}

// Dashboard functionality
let chart = null;

async function initDashboard() {
    try {
        const stations = await fetchJSON('/api/stations');
        const latestReadings = await fetchJSON('/api/readings/latest');
        
        renderStations(stations, latestReadings);
        updateLastUpdated();

        // Wire refresh button
        const refreshBtn = document.getElementById('refreshDashboard');
        if (refreshBtn && !refreshBtn._wired) {
            refreshBtn.addEventListener('click', async () => {
                refreshBtn.disabled = true;
                const originalText = refreshBtn.textContent;
                refreshBtn.textContent = 'Fetching...';
                
                // Show loading indicator
                const loadingDiv = document.createElement('div');
                loadingDiv.id = 'refreshStatus';
                loadingDiv.style.cssText = 'position: fixed; top: 20px; right: 20px; background: #667eea; color: white; padding: 10px 15px; border-radius: 6px; z-index: 1000; font-size: 14px;';
                loadingDiv.textContent = 'Fetching fresh data from AmbientWeather...';
                document.body.appendChild(loadingDiv);
                
                try {
                    // Trigger ingestion to get fresh data
                    refreshBtn.textContent = 'Ingesting...';
                    loadingDiv.textContent = 'Fetching latest readings from API...';
                    await ingestNow();
                    
                    // Re-fetch and rerender with cache-busting
                    refreshBtn.textContent = 'Updating...';
                    loadingDiv.textContent = 'Updating display with fresh data...';
                    const stations = await fetchJSON(`/api/stations?${new URLSearchParams({ _t: Date.now() })}`);
                    const latestReadings = await fetchJSON(`/api/readings/latest?${new URLSearchParams({ _t: Date.now() })}`);
                    renderStations(stations, latestReadings);
                    updateLastUpdated();
                    
                    // Show success message
                    loadingDiv.textContent = '✓ Data updated successfully!';
                    loadingDiv.style.background = '#28a745';
                    setTimeout(() => {
                        if (loadingDiv.parentNode) {
                            loadingDiv.parentNode.removeChild(loadingDiv);
                        }
                    }, 2000);
                    
                } catch (e) {
                    console.error('Refresh failed:', e);
                    loadingDiv.textContent = '✗ Failed to update data';
                    loadingDiv.style.background = '#dc3545';
                    setTimeout(() => {
                        if (loadingDiv.parentNode) {
                            loadingDiv.parentNode.removeChild(loadingDiv);
                        }
                    }, 3000);
                } finally {
                    refreshBtn.textContent = originalText;
                    refreshBtn.disabled = false;
                }
            });
            // mark to avoid double-binding on interval refreshes
            refreshBtn._wired = true;
        }
    } catch (error) {
        console.error('Error initializing dashboard:', error);
        document.getElementById('stationsGrid').innerHTML = 
            '<div class="error">Failed to load station data. Please check your connection.</div>';
    }
}

function renderStations(stations, latestReadings) {
    const grid = document.getElementById('stationsGrid');
    
    if (stations.length === 0) {
        grid.innerHTML = '<div class="loading">No stations found. Run ingestion to discover stations.</div>';
        return;
    }
    
    // Create a map of latest readings by station MAC
    const readingsMap = new Map();
    latestReadings.forEach(reading => {
        readingsMap.set(reading.station_mac, reading);
    });
    
    grid.innerHTML = stations.map(station => {
        const reading = readingsMap.get(station.station_mac);
        // Consider online if either station last_seen or latest reading time is recent
        const ONLINE_WINDOW_MS = 30 * 60 * 1000;
        const lastSeenTimestamp = station.last_seen_utc || (reading && reading.observed_utc) || null;
        const isOnline = lastSeenTimestamp && (Date.now() - lastSeenTimestamp) < ONLINE_WINDOW_MS;
        // Friendly overrides
        const friendly = {
            '48:E7:29:7C:5F:90': 'Property',
            'C8:C9:A3:26:46:28': 'SolarShed73'
        };
        const stationName = friendly[station.station_mac] || station.name || 'Unknown Station';
        
        return `
            <div class="station-card">
                <div class="station-header">
                    <div>
                        <div class="station-name">${stationName}</div>
                        <div class="station-mac">${station.station_mac}</div>
                    </div>
                    <div class="station-status">
                        <div class="status-indicator ${isOnline ? '' : 'offline'}"></div>
                        <span class="status-text">${isOnline ? 'Online' : 'Offline'}</span>
                    </div>
                </div>
                
                ${reading ? renderWeatherData(reading) : '<div class="loading">No recent data</div>'}
                
                <div class="last-seen">
                    Last seen: ${lastSeenTimestamp ? formatTimestamp(new Date(lastSeenTimestamp).toISOString()) : 'Never'}
                </div>
            </div>
        `;
    }).join('');
}

function renderWeatherData(reading) {
    return `
        <div class="weather-grid">
            <div class="weather-item" data-metric="temp_f" data-mac="${reading.station_mac}">
                <div class="weather-label">Temperature</div>
                <div class="weather-value">
                    ${formatValue(reading.temp_f)}<span class="weather-unit">°F</span>
                </div>
            </div>
            <div class="weather-item" data-metric="humidity" data-mac="${reading.station_mac}">
                <div class="weather-label">Humidity</div>
                <div class="weather-value">
                    ${formatValue(reading.humidity)}<span class="weather-unit">%</span>
                </div>
            </div>
            <div class="weather-item" data-metric="pressure_in" data-mac="${reading.station_mac}">
                <div class="weather-label">Pressure</div>
                <div class="weather-value">
                    ${formatValue(reading.pressure_in)}<span class="weather-unit">inHg</span>
                </div>
            </div>
            <div class="weather-item" data-metric="wind_mph" data-mac="${reading.station_mac}">
                <div class="weather-label">Wind Speed</div>
                <div class="weather-value">
                    ${formatValue(reading.wind_mph)}<span class="weather-unit">mph</span>
                </div>
            </div>
            <div class="weather-item" data-metric="wind_gust_mph" data-mac="${reading.station_mac}">
                <div class="weather-label">Wind Gust</div>
                <div class="weather-value">
                    ${formatValue(reading.wind_gust_mph)}<span class="weather-unit">mph</span>
                </div>
            </div>
            <div class="weather-item" data-metric="wind_dir_deg" data-mac="${reading.station_mac}">
                <div class="weather-label">Wind Direction</div>
                <div class="weather-value">
                    ${formatValue(reading.wind_dir_deg)}<span class="weather-unit">°</span>
                </div>
            </div>
            <div class="weather-item" data-metric="rain_hour_in" data-mac="${reading.station_mac}">
                <div class="weather-label">Rain/Hour</div>
                <div class="weather-value">
                    ${formatValue(reading.rain_hour_in)}<span class="weather-unit">in</span>
                </div>
            </div>
            <div class="weather-item" data-metric="rain_daily_in" data-mac="${reading.station_mac}">
                <div class="weather-label">Rain/Daily</div>
                <div class="weather-value">
                    ${formatValue(reading.rain_daily_in)}<span class="weather-unit">in</span>
                </div>
            </div>
            <div class="weather-item" data-metric="uv" data-mac="${reading.station_mac}">
                <div class="weather-label">UV Index</div>
                <div class="weather-value">
                    ${formatValue(reading.uv)}<span class="weather-unit"></span>
                </div>
            </div>
            <div class="weather-item" data-metric="solar_radiation" data-mac="${reading.station_mac}">
                <div class="weather-label">Solar Radiation</div>
                <div class="weather-value">
                    ${formatValue(reading.solar_radiation)}<span class="weather-unit">W/m²</span>
                </div>
            </div>
            <div class="weather-item" data-metric="tempinf" data-mac="${reading.station_mac}">
                <div class="weather-label">Indoor Temperature</div>
                <div class="weather-value">
                    ${formatValue(reading.tempinf)}<span class="weather-unit">°F</span>
                </div>
            </div>
            <div class="weather-item" data-metric="humidityin" data-mac="${reading.station_mac}">
                <div class="weather-label">Indoor Humidity</div>
                <div class="weather-value">
                    ${formatValue(reading.humidityin)}<span class="weather-unit">%</span>
                </div>
            </div>
        </div>
    `;
}

function updateLastUpdated() {
    const now = new Date();
    document.getElementById('lastUpdated').textContent = formatTimestamp(now.toISOString());
}

// History page functionality
let historyChart = null;
let currentData = [];

async function initHistory() {
    try {
        // Initialize date picker
        flatpickr("#dateRange", {
            mode: "range",
            dateFormat: "Y-m-d H:i",
            enableTime: true,
            time_24hr: true,
            defaultDate: [new Date(Date.now() - 24 * 60 * 60 * 1000), new Date()],
            onChange: function(selectedDates) {
                if (selectedDates.length === 2) {
                    updateChart();
                }
            }
        });
        
        // Load stations
        await loadStations();
        
        // Set up event listeners
        document.getElementById('updateChart').addEventListener('click', updateChart);
        document.getElementById('exportCSV').addEventListener('click', exportCSV);
        document.getElementById('stationSelect').addEventListener('change', updateChart);
        document.getElementById('metricSelect').addEventListener('change', updateChart);
        document.getElementById('downsampleSelect').addEventListener('change', updateChart);
        
        // Load initial chart
        await updateChart();
        
    } catch (error) {
        console.error('Error initializing history page:', error);
    }
}

async function loadStations() {
    try {
        const stations = await fetchJSON('/api/stations');
        const select = document.getElementById('stationSelect');
        
        select.innerHTML = '<option value="">All Stations</option>' +
            stations.map(station => 
                `<option value="${station.station_mac}">${station.name || station.station_mac}</option>`
            ).join('');
    } catch (error) {
        console.error('Error loading stations:', error);
    }
}

async function updateChart() {
    try {
        const stationMac = document.getElementById('stationSelect').value;
        const metric = document.getElementById('metricSelect').value;
        const downsample = document.getElementById('downsampleSelect').value;
        const dateRange = document.getElementById('dateRange').value;
        
        // Parse date range
        let from, to;
        if (dateRange) {
            const dates = dateRange.split(' to ');
            from = new Date(dates[0]).toISOString();
            to = new Date(dates[1]).toISOString();
        } else {
            // Default to last 24 hours
            const now = new Date();
            const dayAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000);
            from = dayAgo.toISOString();
            to = now.toISOString();
        }
        
        // Build query parameters
        const params = new URLSearchParams();
        if (stationMac) params.append('station_mac', stationMac);
        if (metric) params.append('metric', metric);
        if (from) params.append('from', from);
        if (to) params.append('to', to);
        if (downsample) params.append('downsample', downsample);
        
        const data = await fetchJSON(`/api/readings?${params}`);
        currentData = data;
        
        renderChart(data, metric);
        renderTable(data, metric);
        
    } catch (error) {
        console.error('Error updating chart:', error);
    }
}

function renderChart(data, metric) {
    const ctx = document.getElementById('weatherChart').getContext('2d');
    
    // Destroy existing chart
    if (historyChart) {
        historyChart.destroy();
    }
    
    // Convert data to Chart.js format with x,y coordinates
    const chartData = data.map(point => ({
        x: point.t,
        y: point.v
    }));
    
    historyChart = new Chart(ctx, {
        type: 'line',
        data: {
            datasets: [{
                label: getMetricLabel(metric),
                data: chartData,
                borderColor: '#667eea',
                backgroundColor: 'rgba(102, 126, 234, 0.1)',
                borderWidth: 2,
                fill: true,
                tension: 0.1
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            interaction: { mode: 'nearest', intersect: false },
            scales: {
                x: {
                    type: 'time',
                    display: true,
                    ticks: { display: false }, // hide bottom axis texts
                    grid: { display: false }
                },
                y: {
                    display: true,
                    title: {
                        display: true,
                        text: getMetricLabel(metric)
                    }
                }
            },
            plugins: {
                legend: {
                    display: true
                },
                tooltip: {
                    callbacks: {
                        title: (context) => {
                            const timestamp = context[0].parsed.x;
                            return new Date(timestamp).toLocaleString('en-US', {
                                timeZone: 'America/Phoenix',
                                year: 'numeric',
                                month: 'short',
                                day: 'numeric',
                                hour: 'numeric',
                                minute: '2-digit',
                                hour12: true
                            });
                        },
                        label: (ctx) => {
                            const val = (ctx.parsed && ctx.parsed.y != null) ? Number(ctx.parsed.y).toFixed(2) : '';
                            const unit = getMetricUnit(metric);
                            return val + (unit ? ' ' + unit : '');
                        }
                    }
                }
            }
        }
    });
}

function renderTable(data, metric) {
    const tbody = document.querySelector('#dataTable tbody');
    const metricHeader = document.getElementById('metricHeader');
    
    metricHeader.textContent = getMetricLabel(metric);
    
    tbody.innerHTML = data.map(point => `
        <tr>
            <td>${formatTimestamp(point.t)}</td>
            <td>${formatValue(point.v)}</td>
        </tr>
    `).join('');
    
    document.getElementById('dataCount').textContent = `${data.length} data points`;
}

function getMetricLabel(metric) {
    const labels = {
        'temp_f': 'Temperature (°F)',
        'humidity': 'Humidity (%)',
        'pressure_in': 'Pressure (inHg)',
        'wind_mph': 'Wind Speed (mph)',
        'wind_gust_mph': 'Wind Gust (mph)',
        'wind_dir_deg': 'Wind Direction (°)',
        'rain_hour_in': 'Rain/Hour (in)',
        'rain_daily_in': 'Rain/Daily (in)',
        'uv': 'UV Index',
        'solar_radiation': 'Solar Radiation',
        'tempinf': 'Indoor Temperature (°F)',
        'humidityin': 'Indoor Humidity (%)'
    };
    return labels[metric] || 'Value';
}

function getMetricUnit(metric) {
    const units = {
        'temp_f': '°F',
        'humidity': '%',
        'pressure_in': 'inHg',
        'wind_mph': 'mph',
        'wind_gust_mph': 'mph',
        'wind_dir_deg': '°',
        'rain_hour_in': 'in',
        'rain_daily_in': 'in',
        'uv': '',
        'solar_radiation': 'W/m²',
        'tempinf': '°F',
        'humidityin': '%'
    };
    return units[metric] || '';
}

function exportCSV() {
    if (currentData.length === 0) {
        alert('No data to export');
        return;
    }
    
    const metric = document.getElementById('metricSelect').value;
    const csvData = currentData.map(point => ({
        timestamp: point.t,
        value: point.v
    }));
    
    const csvContent = [
        'Timestamp,Value',
        ...csvData.map(row => `${row.timestamp},${row.value}`)
    ].join('\n');
    
    const blob = new Blob([csvContent], { type: 'text/csv' });
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `weather_data_${new Date().toISOString().split('T')[0]}.csv`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    window.URL.revokeObjectURL(url);
}

// Initialize based on current page
document.addEventListener('DOMContentLoaded', function() {
    const path = window.location.pathname;
    
    if (path === '/' || path === '/index.html') {
        initDashboard();
        // Refresh dashboard every 5 minutes
        setInterval(initDashboard, 5 * 60 * 1000);
    } else if (path === '/history' || path === '/history.html') {
        initHistory();
    }
    
    // Delegate clicks on metric tiles
    document.addEventListener('click', (e) => {
        try {
            const tile = e.target.closest('.weather-item[data-metric]');
            if (!tile) return;
            const metric = tile.getAttribute('data-metric');
            const mac = tile.getAttribute('data-mac');
            if (metric && mac) {
                openMetricModal(mac, metric);
            }
        } catch (error) {
            console.error('Error handling tile click:', error);
        }
    });
});

// Modal logic
let modalChart;
async function openMetricModal(stationMac, metric) {
    try {
        const modal = document.getElementById('metricModal');
        const title = document.getElementById('modalTitle');
        
        if (!modal) {
            console.error('Modal element not found');
            return;
        }
    
    // Get friendly station name
    const friendly = {
        '48:E7:29:7C:5F:90': 'Property',
        'C8:C9:A3:26:46:28': 'SolarShed73'
    };
    const stationName = friendly[stationMac] || stationMac;
    
    title.textContent = `${getMetricLabel(metric)} — ${stationName}`;

    // Show modal immediately so fetch/render errors don't block opening
    modal.classList.add('show');
    modal.setAttribute('aria-hidden', 'false');

    // fetch last 24 hours (now back)
    const now = new Date();
    const from = new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString();
    const to = now.toISOString();
    const params = new URLSearchParams({ station_mac: stationMac, metric, from, to, downsample: 'none' });
    const data = await fetchJSON(`/api/readings?${params}`);

    // render chart
    const ctx = document.getElementById('modalChart').getContext('2d');
    if (modalChart) modalChart.destroy();
    
    // Convert data to Chart.js format with x,y coordinates
    const chartData = data.map(d => ({
        x: d.t,
        y: d.v
    }));
    
    modalChart = new Chart(ctx, {
        type: 'line',
        data: {
            datasets: [{
                label: getMetricLabel(metric),
                data: chartData,
                borderColor: '#4dabf7',
                backgroundColor: 'rgba(77, 171, 247, 0.15)',
                fill: true,
                tension: 0.1,
                pointRadius: 0
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            interaction: { mode: 'nearest', intersect: false },
            scales: {
                x: { 
                    type: 'time',
                    display: true, 
                    ticks: { display: false }, 
                    grid: { display: false } 
                },
                y: { display: true }
            },
            plugins: {
                tooltip: {
                    callbacks: {
                        title: (context) => {
                            const timestamp = context[0].parsed.x;
                            return new Date(timestamp).toLocaleString('en-US', {
                                timeZone: 'America/Phoenix',
                                year: 'numeric',
                                month: 'short',
                                day: 'numeric',
                                hour: 'numeric',
                                minute: '2-digit',
                                hour12: true
                            });
                        },
                        label: (ctx) => {
                            const val = (ctx.parsed && ctx.parsed.y != null) ? Number(ctx.parsed.y).toFixed(2) : '';
                            const unit = getMetricUnit(metric);
                            return val + (unit ? ' ' + unit : '');
                        }
                    }
                }
            }
        }
    });

    // modal is already shown above

    // closing
    const close = document.getElementById('modalClose');
    const backdrop = document.getElementById('modalBackdrop');
    function hide() {
        modal.classList.remove('show');
        modal.setAttribute('aria-hidden', 'true');
    }
    close.onclick = hide;
    backdrop.onclick = hide;

    // Compare button loads same metric for all stations
    const compareBtn = document.getElementById('modalCompare');
    compareBtn.onclick = async () => {
        compareBtn.disabled = true;
        compareBtn.textContent = 'Loading...';
        try {
            const stations = await fetchJSON('/api/stations');
            const datasets = [];
            const colors = ['#4dabf7','#94d82d','#ff922b','#f06595','#9775fa','#20c997'];
            
            // Create a common time axis from all stations' data
            const allTimePoints = new Set();
            for (const s of stations) {
                const p = new URLSearchParams({ station_mac: s.station_mac, metric, from, to, downsample: 'none' });
                const series = await fetchJSON(`/api/readings?${p}`);
                series.forEach(point => allTimePoints.add(point.t));
            }
            const timeLabels = Array.from(allTimePoints).sort();
            const timeMap = new Map();
            timeLabels.forEach((time, idx) => timeMap.set(time, idx));
            
            let idx = 0;
            for (const s of stations) {
                const p = new URLSearchParams({ station_mac: s.station_mac, metric, from, to, downsample: 'none' });
                const series = await fetchJSON(`/api/readings?${p}`);
                
                // Create data points aligned with common time axis
                const alignedData = timeLabels.map(time => {
                    const point = series.find(p => p.t === time);
                    return {
                        x: time,
                        y: point ? point.v : null
                    };
                });
                
                const label = (s.name || s.station_mac);
                const color = colors[idx % colors.length];
                idx++;
                
                datasets.push({
                    label,
                    data: alignedData,
                    borderColor: color,
                    backgroundColor: color + '22',
                    fill: false,
                    tension: 0.1,
                    pointRadius: 2,
                    spanGaps: false // Don't connect across null values
                });
            }
            
            // Rebuild chart with multiple datasets
            if (modalChart) modalChart.destroy();
            const ctx2 = document.getElementById('modalChart').getContext('2d');
            modalChart = new Chart(ctx2, {
                type: 'line',
                data: {
                    datasets
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    interaction: { mode: 'index', intersect: false },
                    scales: {
                        x: { 
                            type: 'time',
                            display: true, 
                            ticks: { display: false }, 
                            grid: { display: false } 
                        },
                        y: { display: true }
                    },
                    plugins: {
                        tooltip: {
                            mode: 'index',
                            intersect: false,
                            callbacks: {
                                title: (context) => {
                                    const timestamp = context[0].parsed.x;
                                    return new Date(timestamp).toLocaleString('en-US', {
                                        timeZone: 'America/Phoenix',
                                        year: 'numeric',
                                        month: 'short',
                                        day: 'numeric',
                                        hour: 'numeric',
                                        minute: '2-digit',
                                        hour12: true
                                    });
                                },
                                label: (ctx) => {
                                    if (ctx.parsed.y === null) return ctx.dataset.label + ': No data';
                                    const val = Number(ctx.parsed.y).toFixed(2);
                                    const unit = getMetricUnit(metric);
                                    return ctx.dataset.label + ': ' + val + (unit ? ' ' + unit : '');
                                }
                            }
                        }
                    }
                }
            });
            title.textContent = `${getMetricLabel(metric)} — All Stations`;
        } finally {
            compareBtn.textContent = 'Compare';
            compareBtn.disabled = false;
        }
    };
    } catch (error) {
        console.error('Error in openMetricModal:', error);
    }
}

// Trigger ingestion if admin token is available in sessionStorage
async function ingestNow() {
    // Get token from server-side environment (no user interaction needed)
    const tokenResponse = await fetch('/api/admin-token');
    if (!tokenResponse.ok) return; // skip if not available
    const { token } = await tokenResponse.json();
    if (!token) return;
    try {
        await fetchJSON(`/tasks/ingest?token=${encodeURIComponent(token)}`);
    } catch (e) {
        console.warn('Ingest call failed (continuing with refresh):', e.message);
    }
}
