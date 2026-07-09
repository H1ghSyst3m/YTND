import { useRef, type ChangeEvent, type ReactNode } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { motion } from 'framer-motion';
import { Music, Download, Users, CheckCircle, XCircle, AlertCircle, Upload } from 'lucide-react';
import { Button } from './ui/button';
import { Card, CardContent, CardHeader, CardTitle } from './ui/card';
import { useToast } from './ui/toast';
import { useCsrfToken } from '../hooks/useCsrfToken';
import * as api from '../lib/api';

function getStatusIcon(status: string) {
  switch (status) {
    case 'ok':
    case 'present':
      return <CheckCircle className="h-5 w-5 text-green-500" />;
    case 'error':
    case 'missing':
    case 'empty':
    case 'invalid':
      return <XCircle className="h-5 w-5 text-red-500" />;
    default:
      return <AlertCircle className="h-5 w-5 text-yellow-500" />;
  }
}

interface StatusCardProps {
  status: string;
  label: string;
  children?: ReactNode;
  trailing?: ReactNode;
  iconGap?: 'gap-2' | 'gap-3';
}

function StatusCard({ status, label, children, trailing, iconGap = 'gap-2' }: StatusCardProps) {
  return (
    <div className="flex flex-col p-3 bg-muted rounded-lg gap-2">
      <div className={trailing ? 'flex items-center justify-between gap-3' : 'flex items-center gap-2'}>
        <div className={`flex items-center ${iconGap} flex-1 min-w-0`}>
          {getStatusIcon(status)}
          <p className="font-medium text-sm sm:text-base">{label}</p>
        </div>
        {trailing}
      </div>
      {children}
    </div>
  );
}

function DashboardView() {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const queryClient = useQueryClient();
  const { showToast } = useToast();
  const { token: csrfToken } = useCsrfToken();

  const { data, isLoading } = useQuery({
    queryKey: ['dashboard'],
    queryFn: api.getDashboardData,
  });

  const uploadCookiesMutation = useMutation({
    mutationFn: (file: File) => {
      if (!csrfToken) {
        throw new Error('CSRF token is not ready');
      }
      return api.uploadCookiesFile(file, csrfToken);
    },
    onSuccess: (cookiesStatus) => {
      queryClient.setQueryData<api.DashboardData>(['dashboard'], (current) => {
        if (!current?.adminData) return current;
        return {
          ...current,
          adminData: {
            ...current.adminData,
            cookiesStatus,
          },
        };
      });
      queryClient.invalidateQueries({ queryKey: ['dashboard'] });
      showToast('Cookies file uploaded successfully.', 'success');
    },
    onError: (error: Error) => {
      showToast(error.message, 'error');
    },
  });

  const handleCookiesFileChange = (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;

    uploadCookiesMutation.mutate(file);
    event.target.value = '';
  };

  if (isLoading) {
    return <div className="text-center py-8">Loading dashboard...</div>;
  }

  if (!data) {
    return <div className="text-center py-8">No data available</div>;
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -20 }}
      className="space-y-6"
    >
      {/* User Statistics */}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Total Songs</CardTitle>
            <Music className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{data.songCount}</div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Queue Size</CardTitle>
            <Download className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{data.queueSize}</div>
          </CardContent>
        </Card>
      </div>

      {/* Recent Songs List */}
      <Card>
        <CardHeader>
          <CardTitle className="text-lg sm:text-xl">Recently Added Songs</CardTitle>
        </CardHeader>
        <CardContent>
          {data.recentSongs.length > 0 ? (
            <div className="space-y-3">
              {data.recentSongs.map((song, idx) => (
                <div
                  key={idx}
                  className="flex items-center gap-3 p-3 bg-muted rounded-lg"
                >
                  {song.cover_available ? (
                    <img 
                      src={api.getCoverUrl(data.userId, song) || ''}
                      alt={song.title}
                      className="w-12 h-12 object-cover rounded flex-shrink-0"
                    />
                  ) : (
                    <div className="w-12 h-12 bg-secondary rounded flex items-center justify-center flex-shrink-0">
                      <Music className="h-6 w-6 text-muted-foreground" />
                    </div>
                  )}
                  <div className="flex-1 min-w-0">
                    <p className="font-medium truncate text-sm sm:text-base">{song.title}</p>
                    <p className="text-xs sm:text-sm text-muted-foreground truncate">{song.artist}</p>
                  </div>
                  {song.date && (
                    <span className="text-xs sm:text-sm text-muted-foreground ml-2 flex-shrink-0 hidden sm:inline">
                      {song.date}
                    </span>
                  )}
                </div>
              ))}
            </div>
          ) : (
            <p className="text-center text-muted-foreground py-4">No recent songs</p>
          )}
        </CardContent>
      </Card>

      {/* Admin Section */}
      {data.adminData && (
        <>
          <Card>
            <CardHeader>
              <CardTitle className="text-lg sm:text-xl">System Status</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 sm:gap-4">
                {/* Total Users */}
                <div className="flex items-center justify-between p-3 bg-muted rounded-lg">
                  <div className="flex items-center gap-3">
                    <Users className="h-5 w-5 text-muted-foreground flex-shrink-0" />
                    <span className="font-medium text-sm sm:text-base">Total Users</span>
                  </div>
                  <span className="text-base sm:text-lg font-bold">{data.adminData.totalUsers}</span>
                </div>

                <StatusCard status={data.adminData.ytDlpStatus.status} label="yt-dlp">
                  {data.adminData.ytDlpStatus.version && (
                    <p className="text-xs text-muted-foreground break-words">
                      {data.adminData.ytDlpStatus.version}
                      {data.adminData.ytDlpStatus.updateAvailable && (
                        <span className="text-yellow-500 block sm:inline sm:ml-1">
                          (Update: {data.adminData.ytDlpStatus.latest})
                        </span>
                      )}
                    </p>
                  )}
                </StatusCard>

                <StatusCard status={data.adminData.ffmpegStatus.status} label="FFmpeg">
                  {data.adminData.ffmpegStatus.version && (
                    <p className="text-xs text-muted-foreground truncate">
                      {data.adminData.ffmpegStatus.version.substring(0, 50)}
                    </p>
                  )}
                </StatusCard>

                <StatusCard status={data.adminData.jsRuntimeStatus.status} label="JS Runtime">
                  <p className="text-xs text-muted-foreground break-words">
                    {data.adminData.jsRuntimeStatus.runtime || data.adminData.jsRuntimeStatus.status}
                    {data.adminData.jsRuntimeStatus.detail && (
                      <span className="block">{data.adminData.jsRuntimeStatus.detail}</span>
                    )}
                  </p>
                </StatusCard>

                <StatusCard
                  status={data.adminData.cookiesStatus.status}
                  label="Cookies File"
                  iconGap="gap-3"
                  trailing={
                    <div className="flex items-center gap-2 flex-shrink-0">
                      <span className="text-xs sm:text-sm text-muted-foreground">
                        {data.adminData.cookiesStatus.status}
                      </span>
                      <Button
                        type="button"
                        size="sm"
                        variant="outline"
                        className="min-w-24"
                        onClick={() => fileInputRef.current?.click()}
                        disabled={uploadCookiesMutation.isPending || !csrfToken}
                      >
                        <Upload className="h-4 w-4" />
                        {uploadCookiesMutation.isPending ? 'Uploading...' : 'Upload'}
                      </Button>
                      <input
                        ref={fileInputRef}
                        type="file"
                        accept=".txt,text/plain"
                        className="hidden"
                        aria-label="Upload cookies.txt"
                        onChange={handleCookiesFileChange}
                      />
                    </div>
                  }
                >
                  {data.adminData.cookiesStatus.detail && (
                    <p className="text-xs text-muted-foreground break-words">
                      {data.adminData.cookiesStatus.detail}
                    </p>
                  )}
                </StatusCard>

                {/* Log Summary */}
                <div className="flex flex-col p-3 bg-muted rounded-lg gap-2">
                  <p className="font-medium text-sm sm:text-base mb-1">Recent Logs (24h)</p>
                  <div className="flex flex-col sm:flex-row gap-2 sm:gap-4">
                    <div className="flex items-center gap-2">
                      <XCircle className="h-4 w-4 text-red-500" />
                      <span className="text-xs sm:text-sm">
                        {data.adminData.logSummary.error} errors
                      </span>
                    </div>
                    <div className="flex items-center gap-2">
                      <AlertCircle className="h-4 w-4 text-yellow-500" />
                      <span className="text-xs sm:text-sm">
                        {data.adminData.logSummary.warning} warnings
                      </span>
                    </div>
                  </div>
                </div>
              </div>
            </CardContent>
          </Card>
        </>
      )}
    </motion.div>
  );
}

export default DashboardView;
