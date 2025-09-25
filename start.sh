#!/bin/bash

# WeatherStations Startup Script
# Easy management of the WeatherStations server

PROJECT_DIR="/Users/administrator/Documents/WeatherStations"
MONITOR_SCRIPT="$PROJECT_DIR/monitor.sh"

cd "$PROJECT_DIR"

echo "🌤️  WeatherStations Server Management"
echo "====================================="

case "$1" in
    start)
        echo "Starting WeatherStations server..."
        $MONITOR_SCRIPT start
        echo "Starting monitoring process..."
        nohup $MONITOR_SCRIPT monitor > monitor.log 2>&1 &
        echo "✅ Server and monitoring started successfully!"
        echo "📊 Dashboard: http://localhost:3333"
        echo "📈 History: http://localhost:3333/history"
        ;;
    stop)
        echo "Stopping WeatherStations server..."
        pkill -f "monitor.sh monitor"
        $MONITOR_SCRIPT stop
        echo "✅ Server stopped successfully!"
        ;;
    restart)
        echo "Restarting WeatherStations server..."
        pkill -f "monitor.sh monitor"
        $MONITOR_SCRIPT restart
        echo "Starting monitoring process..."
        nohup $MONITOR_SCRIPT monitor > monitor.log 2>&1 &
        echo "✅ Server restarted successfully!"
        ;;
    status)
        echo "Checking server status..."
        $MONITOR_SCRIPT status
        if curl -s http://localhost:3333/health > /dev/null 2>&1; then
            echo "🌐 Server is responding to requests"
        else
            echo "❌ Server is not responding"
        fi
        ;;
    logs)
        echo "Recent server logs:"
        echo "=================="
        tail -20 server.log
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs}"
        echo ""
        echo "Commands:"
        echo "  start   - Start server with monitoring"
        echo "  stop    - Stop server and monitoring"
        echo "  restart - Restart server and monitoring"
        echo "  status  - Check server status"
        echo "  logs    - Show recent server logs"
        echo ""
        echo "The server will automatically restart if it crashes."
        exit 1
        ;;
esac
