import { useState, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { motion } from 'framer-motion';
import { Plus, Trash2, Play, Loader2 } from 'lucide-react';
import { useToast } from './ui/toast';
import { Button } from './ui/button';
import { Card, CardContent, CardHeader, CardTitle } from './ui/card';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from './ui/dialog';
import * as api from '../lib/api';
import { websocketService, type WebSocketMessage } from '../lib/websocket';

interface QueueViewProps {
  userId: string;
}

interface QueueItem {
  url: string;
  status: 'pending' | 'downloading' | 'processing' | 'completed' | 'error';
  title?: string;
  artist?: string;
  id?: string;
  percentage?: number;
  downloaded_bytes?: number;
  total_bytes?: number;
  error?: string;
}

function QueueView({ userId }: QueueViewProps) {
  const { showToast } = useToast();
  const queryClient = useQueryClient();
  const [addDialog, setAddDialog] = useState(false);
  const [urlsText, setUrlsText] = useState('');
  const [queueItems, setQueueItems] = useState<QueueItem[]>([]);
  const [isProcessing, setIsProcessing] = useState(false);

  const { data: queue, isLoading } = useQuery({
    queryKey: ['queue', userId],
    queryFn: () => api.getQueue(userId),
  });

  // Initialize queue items when queue data changes
  useEffect(() => {
    if (queue) {
      setQueueItems(queue.map(url => ({
        url,
        status: 'pending' as const,
      })));
    }
  }, [queue]);

  // Listen for WebSocket messages
  useEffect(() => {
    const handleMessage = (message: WebSocketMessage) => {
      if (message.type === 'download_progress' && message.userId === userId && message.url) {
        setQueueItems(prev => prev.map(item => {
          if (item.url === message.url) {
            return {
              ...item,
              status: message.status as any || item.status,
              title: message.title || item.title,
              artist: message.artist || item.artist,
              id: message.id || item.id,
              percentage: message.percentage,
              downloaded_bytes: message.downloaded_bytes,
              total_bytes: message.total_bytes,
              error: message.error,
            };
          }
          return item;
        }));

        // Remove completed items after a short delay
        if (message.status === 'completed') {
          setTimeout(() => {
            setQueueItems(prev => prev.filter(item => item.url !== message.url));
          }, 2000);
        }
      } else if (message.type === 'download_complete' && message.userId === userId) {
        setIsProcessing(false);
        showToast('Download process completed', 'success');
        queryClient.invalidateQueries({ queryKey: ['queue', userId] });
        queryClient.invalidateQueries({ queryKey: ['songs', userId] });
        queryClient.invalidateQueries({ queryKey: ['dashboard'] });
      } else if (message.type === 'download_error' && message.userId === userId) {
        setIsProcessing(false);
        showToast(`Download process failed: ${message.error}`, 'error');
      } else if (message.type === 'queue_updated' && message.userId === userId) {
        queryClient.invalidateQueries({ queryKey: ['queue', userId] });
      }
    };

    // Subscribe to WebSocket messages
    websocketService.addMessageHandler(handleMessage);

    return () => {
      websocketService.removeMessageHandler(handleMessage);
    };
  }, [userId, queryClient, showToast]);

  const addMutation = useMutation({
    mutationFn: (urls: string[]) => api.addToQueue(userId, urls),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['queue', userId] });
      showToast('URLs added to queue', 'success');
      setAddDialog(false);
      setUrlsText('');
    },
    onError: () => {
      showToast('Failed to add URLs', 'error');
    },
  });

  const removeMutation = useMutation({
    mutationFn: (url: string) => api.removeFromQueue(userId, [url]),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['queue', userId] });
      showToast('URL removed from queue', 'success');
    },
    onError: () => {
      showToast('Failed to remove URL', 'error');
    },
  });

  const clearMutation = useMutation({
    mutationFn: () => api.removeFromQueue(userId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['queue', userId] });
      showToast('Queue cleared', 'success');
    },
    onError: () => {
      showToast('Failed to clear queue', 'error');
    },
  });

  const processMutation = useMutation({
    mutationFn: () => api.processQueue(userId),
    onSuccess: (data) => {
      setIsProcessing(true);
      showToast(`Started processing ${data.queued} item(s)`, 'success');
    },
    onError: (error: Error) => {
      showToast(error.message, 'error');
    },
  });

  const handleAddUrls = () => {
    const urls = urlsText
      .split('\n')
      .map((u) => u.trim())
      .filter((u) => u.length > 0);
    if (urls.length > 0) {
      addMutation.mutate(urls);
    }
  };

  const formatBytes = (bytes: number) => {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i];
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'pending':
        return 'text-gray-500';
      case 'downloading':
        return 'text-blue-500';
      case 'processing':
        return 'text-yellow-500';
      case 'completed':
        return 'text-green-500';
      case 'error':
        return 'text-red-500';
      default:
        return 'text-gray-500';
    }
  };

  const getStatusText = (item: QueueItem) => {
    switch (item.status) {
      case 'pending':
        return 'Pending';
      case 'downloading':
        if (item.percentage !== undefined) {
          const downloadedStr = item.downloaded_bytes ? formatBytes(item.downloaded_bytes) : '';
          const totalStr = item.total_bytes ? formatBytes(item.total_bytes) : '';
          return `Downloading ${item.percentage.toFixed(1)}%${downloadedStr && totalStr ? ` (${downloadedStr} / ${totalStr})` : ''}`;
        }
        return 'Downloading...';
      case 'processing':
        return 'Processing...';
      case 'completed':
        return 'Completed';
      case 'error':
        return `Error: ${item.error || 'Unknown error'}`;
      default:
        return 'Unknown';
    }
  };

  if (isLoading) {
    return <div className="text-center py-8">Loading queue...</div>;
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -20 }}
    >
      <Card>
        <CardHeader>
          <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 w-full">
            <CardTitle>Download Queue for {userId}</CardTitle>
            <div className="flex flex-col sm:flex-row gap-2 w-full sm:w-auto">
              <Button onClick={() => setAddDialog(true)} className="w-full sm:w-auto">
                <Plus className="mr-2 h-4 w-4" />
                Add URLs
              </Button>
              {queueItems && queueItems.length > 0 && (
                <>
                  <Button 
                    onClick={() => processMutation.mutate()} 
                    disabled={isProcessing || processMutation.isPending}
                    className="w-full sm:w-auto"
                  >
                    {isProcessing ? (
                      <>
                        <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                        Processing...
                      </>
                    ) : (
                      <>
                        <Play className="mr-2 h-4 w-4" />
                        Start Download
                      </>
                    )}
                  </Button>
                  <Button 
                    variant="destructive" 
                    onClick={() => clearMutation.mutate()} 
                    disabled={isProcessing}
                    className="w-full sm:w-auto"
                  >
                    Clear Queue
                  </Button>
                </>
              )}
            </div>
          </div>
        </CardHeader>
        <CardContent>
          {queueItems && queueItems.length > 0 ? (
            <div className="space-y-2">
              {queueItems.map((item, idx) => (
                <div
                  key={idx}
                  className="flex flex-col p-3 bg-muted rounded-lg"
                >
                  <div className="flex items-start justify-between mb-2">
                    <div className="flex-1 mr-4">
                      {item.title ? (
                        <div className="font-medium">{item.title}</div>
                      ) : null}
                      {item.artist ? (
                        <div className="text-sm text-muted-foreground">{item.artist}</div>
                      ) : null}
                      <div className="text-xs text-muted-foreground truncate">{item.url}</div>
                    </div>
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => removeMutation.mutate(item.url)}
                      disabled={isProcessing}
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </div>
                  <div className={`text-sm font-medium ${getStatusColor(item.status)}`}>
                    {getStatusText(item)}
                  </div>
                  {item.status === 'downloading' && item.percentage !== undefined && (
                    <div className="w-full bg-gray-200 rounded-full h-2 mt-2">
                      <div
                        className="bg-blue-600 h-2 rounded-full transition-all duration-300"
                        style={{ width: `${item.percentage}%` }}
                      />
                    </div>
                  )}
                </div>
              ))}
            </div>
          ) : (
            <div className="text-center text-muted-foreground py-8">
              Queue is empty
            </div>
          )}
        </CardContent>
      </Card>

      <Dialog open={addDialog} onOpenChange={setAddDialog}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Add URLs to Queue</DialogTitle>
            <DialogDescription>
              Enter YouTube URLs, one per line
            </DialogDescription>
          </DialogHeader>
          <textarea
            className="w-full h-40 bg-background border border-input rounded-md px-3 py-2 text-sm resize-none"
            value={urlsText}
            onChange={(e) => setUrlsText(e.target.value)}
            placeholder="https://youtube.com/watch?v=..."
          />
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setAddDialog(false)}>
              Cancel
            </Button>
            <Button
              onClick={handleAddUrls}
              disabled={!urlsText.trim() || addMutation.isPending}
            >
              Add to Queue
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </motion.div>
  );
}

export default QueueView;
