#!/bin/bash

# WeatherStations Server Monitor
# This script monitors the server and restarts it if it crashes

SERVER_PID_FILE="/Users/administrator/Documents/WeatherStations/server.pid"
LOG_FILE="/Users/administrator/Documents/WeatherStations/server.log"
PROJECT_DIR="/Users/administrator/Documents/WeatherStations"

# Function to start the server
start_server() {
    echo "$(date): Starting WeatherStations server..." >> "$LOG_FILE"
    cd "$PROJECT_DIR"
    nohup npm start >> "$LOG_FILE" 2>&1 &
    echo $! > "$SERVER_PID_FILE"
    echo "$(date): Server started with PID $(cat $SERVER_PID_FILE)" >> "$LOG_FILE"
}

# Function to check if server is running
is_server_running() {
    if [ -f "$SERVER_PID_FILE" ]; then
        local pid=$(cat "$SERVER_PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            # Check if it's actually responding
            if curl -s http://localhost:3333/health > /dev/null 2>&1; then
                return 0
            else
                echo "$(date): Server PID $pid exists but not responding" >> "$LOG_FILE"
                return 1
            fi
        else
            echo "$(date): Server PID $pid not found in process list" >> "$LOG_FILE"
            return 1
        fi
    else
        echo "$(date): No PID file found" >> "$LOG_FILE"
        return 1
    fi
}

# Function to stop the server
stop_server() {
    if [ -f "$SERVER_PID_FILE" ]; then
        local pid=$(cat "$SERVER_PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo "$(date): Stopping server PID $pid" >> "$LOG_FILE"
            kill "$pid"
            sleep 2
            if ps -p "$pid" > /dev/null 2>&1; then
                echo "$(date): Force killing server PID $pid" >> "$LOG_FILE"
                kill -9 "$pid"
            fi
        fi
        rm -f "$SERVER_PID_FILE"
    fi
}

# Main monitoring loop
monitor_server() {
    echo "$(date): Starting WeatherStations server monitor..." >> "$LOG_FILE"
    
    while true; do
        if ! is_server_running; then
            echo "$(date): Server not running, restarting..." >> "$LOG_FILE"
            start_server
            sleep 10  # Wait for server to fully start
        else
            echo "$(date): Server is running normally (PID: $(cat $SERVER_PID_FILE))" >> "$LOG_FILE"
        fi
        
        sleep 30  # Check every 30 seconds
    done
}

# Handle script arguments
case "$1" in
    start)
        start_server
        ;;
    stop)
        stop_server
        ;;
    restart)
        stop_server
        sleep 2
        start_server
        ;;
    status)
        if is_server_running; then
            echo "Server is running (PID: $(cat $SERVER_PID_FILE))"
        else
            echo "Server is not running"
        fi
        ;;
    monitor)
        monitor_server
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|monitor}"
        echo "  start   - Start the server"
        echo "  stop    - Stop the server"
        echo "  restart - Restart the server"
        echo "  status  - Check server status"
        echo "  monitor - Run continuous monitoring"
        exit 1
        ;;
esac
