// WebSocket client for real-time updates
import { QueryClient } from '@tanstack/react-query';

export interface WebSocketMessage {
  type: 'songs_updated' | 'queue_updated' | 'users_updated' | 'dashboard_updated' | 'logs_updated' | 'pong' | 'download_progress' | 'download_complete' | 'download_error';
  userId?: string;
  url?: string;
  status?: string;
  title?: string;
  artist?: string;
  id?: string;
  percentage?: number;
  downloaded_bytes?: number;
  total_bytes?: number;
  error?: string;
  result?: unknown;
}

type MessageHandler = (message: WebSocketMessage) => void;

const logDev = (...args: unknown[]) => {
  if (import.meta.env.DEV) {
    console.debug(...args);
  }
};

const warnDev = (...args: unknown[]) => {
  if (import.meta.env.DEV) {
    console.warn(...args);
  }
};

class WebSocketService {
  private ws: WebSocket | null = null;
  private queryClient: QueryClient | null = null;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 5;
  private reconnectDelay = 1000; // Start with 1 second
  private reconnectTimeout: ReturnType<typeof setTimeout> | null = null;
  private pingInterval: ReturnType<typeof setInterval> | null = null;
  private isConnecting = false;
  private customHandlers: Set<MessageHandler> = new Set();
  private shouldReconnect = false;

  connect(queryClient: QueryClient) {
    this.shouldReconnect = true;

    if (this.ws?.readyState === WebSocket.OPEN || this.isConnecting) {
      return;
    }

    this.isConnecting = true;
    this.queryClient = queryClient;

    // Determine WebSocket URL
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = `${protocol}//${window.location.host}/api/ws`;

    logDev('[WebSocket] Connecting to:', wsUrl);

    try {
      this.ws = new WebSocket(wsUrl);

      this.ws.onopen = () => {
        logDev('[WebSocket] Connected');
        this.isConnecting = false;
        this.reconnectAttempts = 0;
        this.reconnectDelay = 1000;

        // Start ping interval to keep connection alive
        this.startPingInterval();
      };

      this.ws.onmessage = (event) => {
        try {
          const message: WebSocketMessage = JSON.parse(event.data);
          this.handleMessage(message);
        } catch (error) {
          warnDev('[WebSocket] Failed to parse message:', error);
        }
      };

      this.ws.onerror = (error) => {
        warnDev('[WebSocket] Error:', error);
        this.isConnecting = false;
      };

      this.ws.onclose = () => {
        logDev('[WebSocket] Connection closed');
        this.isConnecting = false;
        this.stopPingInterval();
        if (this.shouldReconnect) {
          this.scheduleReconnect();
        }
      };
    } catch (error) {
      warnDev('[WebSocket] Failed to create connection:', error);
      this.isConnecting = false;
      this.scheduleReconnect();
    }
  }

  disconnect() {
    logDev('[WebSocket] Disconnecting');
    this.shouldReconnect = false;
    this.stopPingInterval();
    
    if (this.reconnectTimeout) {
      clearTimeout(this.reconnectTimeout);
      this.reconnectTimeout = null;
    }

    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }

    this.reconnectAttempts = 0;
    this.isConnecting = false;
    this.queryClient = null;
  }

  addMessageHandler(handler: MessageHandler) {
    this.customHandlers.add(handler);
  }

  removeMessageHandler(handler: MessageHandler) {
    this.customHandlers.delete(handler);
  }

  private handleMessage(message: WebSocketMessage) {
    if (!this.queryClient) return;

    logDev('[WebSocket] Received message:', message);

    // Call custom handlers first
    this.customHandlers.forEach(handler => {
      try {
        handler(message);
      } catch (error) {
        warnDev('[WebSocket] Custom handler error:', error);
      }
    });

    // Handle default message types
    switch (message.type) {
      case 'pong':
        // Keep-alive response, no action needed
        break;

      case 'songs_updated':
        if (message.userId) {
          // Invalidate songs query for the specific user
          this.queryClient.invalidateQueries({ queryKey: ['songs', message.userId] });
          // Also invalidate dashboard as it shows recent songs
          this.queryClient.invalidateQueries({ queryKey: ['dashboard'] });
        }
        break;

      case 'queue_updated':
        if (message.userId) {
          // Invalidate queue query for the specific user
          this.queryClient.invalidateQueries({ queryKey: ['queue', message.userId] });
          // Also invalidate dashboard as it shows queue size
          this.queryClient.invalidateQueries({ queryKey: ['dashboard'] });
        }
        break;

      case 'users_updated':
        // Invalidate users list (admin only)
        this.queryClient.invalidateQueries({ queryKey: ['users-detailed'] });
        // Also invalidate dashboard as it shows total users
        this.queryClient.invalidateQueries({ queryKey: ['dashboard'] });
        break;

      case 'dashboard_updated':
        // Invalidate dashboard data
        this.queryClient.invalidateQueries({ queryKey: ['dashboard'] });
        break;

      case 'logs_updated':
        // Invalidate logs query (admin only)
        this.queryClient.invalidateQueries({ queryKey: ['logs'] });
        break;

      case 'download_progress':
      case 'download_complete':
      case 'download_error':
        // These are handled by custom handlers in components
        break;

      default:
        warnDev('[WebSocket] Unknown message type:', message.type);
    }
  }

  private scheduleReconnect() {
    if (!this.shouldReconnect) {
      return;
    }

    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      logDev('[WebSocket] Max reconnect attempts reached, giving up');
      return;
    }

    if (this.reconnectTimeout) {
      return; // Already scheduled
    }

    const delay = this.reconnectDelay * Math.pow(2, this.reconnectAttempts);
    logDev(`[WebSocket] Scheduling reconnect in ${delay}ms (attempt ${this.reconnectAttempts + 1}/${this.maxReconnectAttempts})`);

    this.reconnectTimeout = setTimeout(() => {
      this.reconnectTimeout = null;
      this.reconnectAttempts++;
      
      if (this.queryClient && this.shouldReconnect) {
        this.connect(this.queryClient);
      }
    }, delay);
  }

  private startPingInterval() {
    this.stopPingInterval();
    
    // Send ping every 30 seconds to keep connection alive
    this.pingInterval = setInterval(() => {
      if (this.ws?.readyState === WebSocket.OPEN) {
        this.ws.send('ping');
      }
    }, 30000);
  }

  private stopPingInterval() {
    if (this.pingInterval) {
      clearInterval(this.pingInterval);
      this.pingInterval = null;
    }
  }
}

// Export a singleton instance
export const websocketService = new WebSocketService();
