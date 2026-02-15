using NAudio.Wave;
using System.IO;

namespace HolaAI.Windows.Services;

public sealed class AudioCaptureService : IDisposable
{
    private WaveInEvent? _waveIn;
    private WaveFileWriter? _writer;
    private string? _currentFilePath;

    public bool IsRecording { get; private set; }

    public event Action<float>? AudioLevelChanged;

    public Task<string> StartAsync(CancellationToken cancellationToken = default)
    {
        if (IsRecording)
        {
            throw new InvalidOperationException("Audio capture is already running.");
        }

        _currentFilePath = Path.Combine(Path.GetTempPath(), $"hola-ai-{Guid.NewGuid():N}.wav");
        _waveIn = new WaveInEvent
        {
            WaveFormat = new WaveFormat(16000, 1),
            BufferMilliseconds = 100
        };
        _writer = new WaveFileWriter(_currentFilePath, _waveIn.WaveFormat);

        _waveIn.DataAvailable += (_, args) =>
        {
            _writer?.Write(args.Buffer, 0, args.BytesRecorded);
            _writer?.Flush();

            var level = CalculatePeak(args.Buffer, args.BytesRecorded);
            AudioLevelChanged?.Invoke(level);
        };

        _waveIn.RecordingStopped += (_, _) =>
        {
            _writer?.Dispose();
            _writer = null;
            _waveIn?.Dispose();
            _waveIn = null;
            IsRecording = false;
        };

        _waveIn.StartRecording();
        IsRecording = true;
        return Task.FromResult(_currentFilePath);
    }

    public Task<string?> StopAsync(CancellationToken cancellationToken = default)
    {
        if (!IsRecording)
        {
            return Task.FromResult<string?>(null);
        }

        _waveIn?.StopRecording();
        return Task.FromResult(_currentFilePath);
    }

    public void Dispose()
    {
        _writer?.Dispose();
        _waveIn?.Dispose();
    }

    private static float CalculatePeak(byte[] buffer, int bytesRecorded)
    {
        if (bytesRecorded < 2)
        {
            return 0;
        }

        var peak = 0f;
        for (var i = 0; i < bytesRecorded; i += 2)
        {
            var sample = BitConverter.ToInt16(buffer, i) / 32768f;
            var abs = Math.Abs(sample);
            if (abs > peak)
            {
                peak = abs;
            }
        }

        return Math.Clamp(peak, 0f, 1f);
    }
}
