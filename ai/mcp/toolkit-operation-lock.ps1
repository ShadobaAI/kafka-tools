param([switch]$Hold)

# Kernel ownership is shared by the Windows CLI and GUI. Process exit closes the
# handle, so a crash cannot leave a stale lock file.
function Enter-KafkaToolkitOperation {
    $mutex = [Threading.Mutex]::new($false, 'Global\KafkaAI.Toolkit.Operation.v1')
    try {
        try { $acquired = $mutex.WaitOne(0) }
        catch [Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) {
            throw 'Another Kafka toolkit operation is running. Wait for it to finish (GUI or CLI).'
        }
        return $mutex
    }
    catch { $mutex.Dispose(); throw }
}

if ($Hold) {
    $ErrorActionPreference = 'Stop'
    $mutex = $null
    try {
        $mutex = Enter-KafkaToolkitOperation
        [Console]::Out.WriteLine('LOCKED')
        [Console]::Out.Flush()
        # EOF releases the lock even if the Node parent crashes.
        $null = [Console]::In.ReadLine()
    }
    catch {
        [Console]::Error.WriteLine('Kafka toolkit is busy or its Windows operation lock is unavailable.')
        exit 73
    }
    finally {
        if ($null -ne $mutex) { $mutex.ReleaseMutex(); $mutex.Dispose() }
    }
}
