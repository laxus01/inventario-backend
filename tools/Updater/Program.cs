using System.Diagnostics;
using System.IO.Compression;
using System.Net;
using System.Security.Principal;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace InventarioUpdater;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Contains("--verify", StringComparer.Ordinal))
        {
            try
            {
                ReleaseUpdater.VerifyEmbeddedPayload();
                return 0;
            }
            catch
            {
                return 1;
            }
        }

        if (!IsAdministrator())
        {
            try
            {
                Process.Start(new ProcessStartInfo(Application.ExecutablePath)
                {
                    UseShellExecute = true,
                    Verb = "runas"
                });
            }
            catch (System.ComponentModel.Win32Exception exception) when (exception.NativeErrorCode == 1223)
            {
                return 0;
            }

            return 0;
        }

        ApplicationConfiguration.Initialize();
        Application.Run(new UpdateForm());
        return 0;
    }

    private static bool IsAdministrator()
    {
        using var identity = WindowsIdentity.GetCurrent();
        return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
    }
}

internal sealed class UpdateForm : Form
{
    private readonly TextBox _projectPath = new()
    {
        Dock = DockStyle.Fill,
        Text = FindProjectRoot()
    };

    private readonly RichTextBox _log = new()
    {
        Dock = DockStyle.Fill,
        ReadOnly = true,
        DetectUrls = false
    };

    private readonly Button _updateButton = new()
    {
        Text = "Actualizar backend y aplicación web",
        AutoSize = true,
        Anchor = AnchorStyles.Left
    };

    private bool _updating;

    public UpdateForm()
    {
        var version = ReleaseUpdater.GetEmbeddedVersion();
        Text = $"Actualizador de Inventario — versión {version}";
        MinimumSize = new Size(700, 430);
        Size = new Size(820, 520);
        StartPosition = FormStartPosition.CenterScreen;

        var layout = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(14),
            ColumnCount = 3,
            RowCount = 5
        };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 12));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 110));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 28));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 44));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

        var pathLabel = new Label
        {
            Text = "Selecciona la raíz Inventario Movil (contiene inventario e inventario-backend):",
            Dock = DockStyle.Fill,
            TextAlign = ContentAlignment.MiddleLeft
        };
        layout.Controls.Add(pathLabel, 0, 0);
        layout.SetColumnSpan(pathLabel, 3);
        layout.Controls.Add(_projectPath, 0, 1);
        layout.SetColumnSpan(_projectPath, 2);

        var browseButton = new Button
        {
            Text = "Examinar...",
            Dock = DockStyle.Fill
        };
        browseButton.Click += BrowseForInstallPath;
        layout.Controls.Add(browseButton, 2, 1);

        var explanation = new Label
        {
            Text = "Se actualizan inventario-backend\\dist e inventario\\www. Se conservan .env y la base de datos.",
            Dock = DockStyle.Fill,
            TextAlign = ContentAlignment.MiddleLeft
        };
        layout.Controls.Add(explanation, 0, 2);
        layout.SetColumnSpan(explanation, 3);

        _updateButton.Click += Update;
        layout.Controls.Add(_updateButton, 0, 3);
        layout.SetColumnSpan(_updateButton, 3);
        layout.Controls.Add(_log, 0, 4);
        layout.SetColumnSpan(_log, 3);
        Controls.Add(layout);
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (_updating)
        {
            e.Cancel = true;
        }

        base.OnFormClosing(e);
    }

    private void BrowseForInstallPath(object? sender, EventArgs e)
    {
        using var dialog = new FolderBrowserDialog
        {
            Description = "Selecciona la raíz que contiene inventario e inventario-backend",
            UseDescriptionForTitle = true,
            SelectedPath = Directory.Exists(_projectPath.Text) ? _projectPath.Text : @"C:\"
        };

        if (dialog.ShowDialog(this) == DialogResult.OK)
        {
            _projectPath.Text = dialog.SelectedPath;
        }
    }

    private async void Update(object? sender, EventArgs e)
    {
        if (string.IsNullOrWhiteSpace(_projectPath.Text))
        {
            MessageBox.Show(this, "Selecciona la carpeta raíz Inventario Movil.", "Carpeta no válida");
            return;
        }

        string projectPath;
        try
        {
            projectPath = Path.GetFullPath(_projectPath.Text.Trim());
        }
        catch (Exception)
        {
            MessageBox.Show(this, "La carpeta seleccionada no es válida.", "Carpeta no válida");
            return;
        }
        if (!HasProjectLayout(projectPath))
        {
            MessageBox.Show(
                this,
                "La carpeta seleccionada debe contener inventario\\ y inventario-backend\\, con .env y dist\\server.js dentro del backend.",
                "Carpeta no válida",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
            return;
        }

        if (MessageBox.Show(
                this,
                $"Se actualizarán:\n{Path.Combine(projectPath, "inventario-backend", "dist")}\n{Path.Combine(projectPath, "inventario", "www")}\n\nSe guardará un respaldo. No se cambiará .env ni se ejecutarán migraciones de base de datos.\n\n¿Continuar?",
                "Confirmar actualización",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Question) != DialogResult.Yes)
        {
            return;
        }

        _updating = true;
        _updateButton.Enabled = false;
        _projectPath.Enabled = false;
        Log($"Iniciando actualización incluida: {ReleaseUpdater.GetEmbeddedVersion()}");

        try
        {
            var backupPath = await ReleaseUpdater.ApplyAsync(projectPath, Log);
            Log($"Actualización verificada. Respaldo: {backupPath}");
            MessageBox.Show(
                this,
                $"Actualización completada y verificada.\n\nRespaldo anterior:\n{backupPath}\n\nEn los navegadores, recarga la aplicación con Ctrl+F5.",
                "Actualización completada",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
        }
        catch (Exception exception)
        {
            Log($"ERROR: {exception.Message}");
            MessageBox.Show(
                this,
                exception.Message,
                "No se pudo completar la actualización",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
        finally
        {
            _updating = false;
            _updateButton.Enabled = true;
            _projectPath.Enabled = true;
        }
    }

    private void Log(string message)
    {
        if (InvokeRequired)
        {
            BeginInvoke(new Action(() => Log(message)));
            return;
        }

        _log.AppendText($"[{DateTime.Now:HH:mm:ss}] {message}{Environment.NewLine}");
        _log.SelectionStart = _log.TextLength;
        _log.ScrollToCaret();
    }

    private static string FindProjectRoot()
    {
        var current = new DirectoryInfo(AppContext.BaseDirectory);
        for (var depth = 0; current is not null && depth < 6; depth++, current = current.Parent)
        {
            if (HasProjectLayout(current.FullName))
            {
                return current.FullName;
            }
        }

        return string.Empty;
    }

    private static bool HasProjectLayout(string projectPath)
    {
        var backendPath = Path.Combine(projectPath, "inventario-backend");
        return Directory.Exists(Path.Combine(projectPath, "inventario"))
            && File.Exists(Path.Combine(backendPath, ".env"))
            && File.Exists(Path.Combine(backendPath, "dist", "server.js"));
    }
}

internal static class ReleaseUpdater
{
    private const string ServiceName = "InventarioAPI";
    private const int ServiceStopped = 1;
    private const int ServiceRunning = 4;
    private static readonly HttpClient HttpClient = new() { Timeout = TimeSpan.FromSeconds(4) };

    public static string GetEmbeddedVersion()
    {
        using var archive = OpenPayload();
        var entry = archive.GetEntry("release.json")
            ?? throw new InvalidOperationException("El paquete incluido no contiene release.json.");
        using var reader = new StreamReader(entry.Open());
        using var manifest = JsonDocument.Parse(reader.ReadToEnd());
        return manifest.RootElement.GetProperty("version").GetString()
            ?? throw new InvalidOperationException("La versión del paquete no es válida.");
    }

    public static void VerifyEmbeddedPayload()
    {
        using var archive = OpenPayload();
        var entries = archive.Entries.Select(entry => entry.FullName.Replace('\\', '/')).ToHashSet(StringComparer.Ordinal);
        if (!entries.Contains("inventario-backend/dist/server.js")
            || !entries.Contains("inventario/www/index.html")
            || !entries.Contains("release.json"))
        {
            throw new InvalidOperationException("El paquete incluido no contiene los archivos esperados.");
        }

        _ = GetEmbeddedVersion();
    }

    public static async Task<string> ApplyAsync(string projectPath, Action<string> log)
    {
        var backendPath = Path.Combine(projectPath, "inventario-backend");
        var frontendPath = Path.Combine(projectPath, "inventario");
        var backendDist = Path.Combine(backendPath, "dist");
        var frontendBuild = Path.Combine(frontendPath, "www");
        var updateRoot = Path.Combine(projectPath, ".updates");
        var stagingPath = Path.Combine(updateRoot, $"staging-{Guid.NewGuid():N}");
        Directory.CreateDirectory(stagingPath);

        try
        {
            ExtractPayload(stagingPath);
            ValidatePayload(stagingPath);

            var port = ReadPort(Path.Combine(backendPath, ".env"));
            var serviceState = await GetServiceStateAsync();
            if (serviceState != ServiceRunning)
            {
                throw new InvalidOperationException(
                    "El servicio InventarioAPI no está en ejecución. Inícialo y vuelve a ejecutar el actualizador.");
            }

            var backupPath = Path.Combine(
                updateRoot,
                "backups",
                $"{DateTime.Now:yyyyMMdd-HHmmss}-{Guid.NewGuid():N}");
            Directory.CreateDirectory(Path.GetDirectoryName(backupPath)!);

            var oldBackendMoved = false;
            var oldFrontendMoved = false;
            var newBackendMoved = false;
            var newFrontendMoved = false;
            var filesTouched = false;

            try
            {
                log("Deteniendo el servicio InventarioAPI...");
                await StopServiceAsync();
                Directory.CreateDirectory(backupPath);

                Directory.Move(backendDist, Path.Combine(backupPath, "inventario-backend-dist"));
                oldBackendMoved = true;
                filesTouched = true;
                if (Directory.Exists(frontendBuild))
                {
                    Directory.Move(frontendBuild, Path.Combine(backupPath, "inventario-www"));
                    oldFrontendMoved = true;
                }

                Directory.Move(Path.Combine(stagingPath, "inventario-backend", "dist"), backendDist);
                newBackendMoved = true;
                Directory.Move(Path.Combine(stagingPath, "inventario", "www"), frontendBuild);
                newFrontendMoved = true;

                log("Archivos actualizados. Iniciando el servicio...");
                await StartServiceAsync();
                await VerifyHealthAsync(port, log);
                return backupPath;
            }
            catch (Exception updateException)
            {
                if (filesTouched)
                {
                    log("La comprobación falló; restaurando los archivos respaldados...");
                    try
                    {
                        await StopServiceAsync();
                        var failedPath = Path.Combine(updateRoot, "failed", $"{DateTime.Now:yyyyMMdd-HHmmss}-{Guid.NewGuid():N}");
                        Directory.CreateDirectory(failedPath);

                        if (newFrontendMoved && Directory.Exists(frontendBuild))
                        {
                            Directory.Move(frontendBuild, Path.Combine(failedPath, "inventario-www"));
                        }

                        if (newBackendMoved && Directory.Exists(backendDist))
                        {
                            Directory.Move(backendDist, Path.Combine(failedPath, "inventario-backend-dist"));
                        }

                        if (oldFrontendMoved && Directory.Exists(Path.Combine(backupPath, "inventario-www")))
                        {
                            Directory.Move(Path.Combine(backupPath, "inventario-www"), frontendBuild);
                        }

                        if (oldBackendMoved && Directory.Exists(Path.Combine(backupPath, "inventario-backend-dist")))
                        {
                            Directory.Move(Path.Combine(backupPath, "inventario-backend-dist"), backendDist);
                        }

                        log("Respaldo restaurado. Iniciando el servicio con la versión anterior...");
                        await StartServiceAsync();
                    }
                    catch (Exception rollbackException)
                    {
                        throw new InvalidOperationException(
                            $"Falló la actualización ({updateException.Message}) y también la restauración ({rollbackException.Message}). Revisa el respaldo en: {backupPath}",
                            rollbackException);
                    }
                }
                else
                {
                    try
                    {
                        await StartServiceAsync();
                    }
                    catch
                    {
                    }
                }

                throw new InvalidOperationException(
                    $"No se pudo completar la actualización. La versión anterior se conserva o fue restaurada. Respaldo: {backupPath}. Detalle: {updateException.Message}",
                    updateException);
            }
        }
        finally
        {
            if (Directory.Exists(stagingPath))
            {
                try
                {
                    Directory.Delete(stagingPath, true);
                }
                catch (IOException)
                {
                }
                catch (UnauthorizedAccessException)
                {
                }
            }
        }
    }

    private static ZipArchive OpenPayload()
    {
        var stream = typeof(ReleaseUpdater).Assembly.GetManifestResourceStream("UpdatePayload.zip")
            ?? throw new InvalidOperationException("Este ejecutable no contiene un paquete de actualización.");
        return new ZipArchive(stream, ZipArchiveMode.Read);
    }

    private static void ExtractPayload(string destination)
    {
        var root = Path.GetFullPath(destination) + Path.DirectorySeparatorChar;
        using var archive = OpenPayload();
        foreach (var entry in archive.Entries)
        {
            var relativePath = entry.FullName.Replace('\\', '/');
            var segments = relativePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
            if (segments.Length == 0 || segments.Any(segment => segment is "." or ".."))
            {
                throw new InvalidOperationException("El paquete contiene una ruta no permitida.");
            }

            var allowedPath = segments[0] == "release.json" && segments.Length == 1
                || segments[0] == "inventario-backend"
                    && (segments.Length == 1 || segments[1] == "dist")
                || segments[0] == "inventario"
                    && (segments.Length == 1 || segments[1] == "www");
            if (!allowedPath)
            {
                throw new InvalidOperationException("El paquete contiene una ruta no permitida.");
            }

            var fullPath = Path.GetFullPath(Path.Combine(destination, relativePath.Replace('/', Path.DirectorySeparatorChar)));
            if (!fullPath.StartsWith(root, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException("El paquete intenta escribir fuera de la carpeta temporal.");
            }

            if (relativePath.EndsWith('/'))
            {
                Directory.CreateDirectory(fullPath);
                continue;
            }

            Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
            entry.ExtractToFile(fullPath);
        }
    }

    private static void ValidatePayload(string stagingPath)
    {
        if (!File.Exists(Path.Combine(stagingPath, "inventario-backend", "dist", "server.js"))
            || !File.Exists(Path.Combine(stagingPath, "inventario", "www", "index.html"))
            || !File.Exists(Path.Combine(stagingPath, "release.json")))
        {
            throw new InvalidOperationException("El paquete no contiene un backend y una aplicación web completos.");
        }

        using var manifest = JsonDocument.Parse(File.ReadAllText(Path.Combine(stagingPath, "release.json")));
        var version = manifest.RootElement.GetProperty("version").GetString();
        if (string.IsNullOrWhiteSpace(version))
        {
            throw new InvalidOperationException("La versión incluida en el paquete no es válida.");
        }
    }

    private static int ReadPort(string envPath)
    {
        foreach (var line in File.ReadLines(envPath))
        {
            var trimmed = line.Trim();
            if (!trimmed.StartsWith("PORT=", StringComparison.Ordinal))
            {
                continue;
            }

            var value = trimmed["PORT=".Length..].Trim().Trim('"', '\'');
            if (int.TryParse(value, out var port) && port is > 0 and <= 65535)
            {
                return port;
            }

            throw new InvalidOperationException("El valor PORT del archivo .env no es válido.");
        }

        return 3000;
    }

    private static async Task<int> GetServiceStateAsync()
    {
        var result = await RunServiceCommandAsync("query");
        if (result.ExitCode != 0)
        {
            throw new InvalidOperationException("No se encontró el servicio de Windows InventarioAPI.");
        }

        var match = Regex.Match(result.Output, @"(?:STATE|ESTADO)\s*:\s*(\d+)", RegexOptions.IgnoreCase);
        if (!match.Success || !int.TryParse(match.Groups[1].Value, out var state))
        {
            throw new InvalidOperationException("No se pudo determinar el estado del servicio InventarioAPI.");
        }

        return state;
    }

    private static async Task StopServiceAsync()
    {
        var state = await GetServiceStateAsync();
        if (state == ServiceStopped)
        {
            return;
        }

        await RunServiceCommandAsync("stop");
        await WaitForServiceStateAsync(ServiceStopped);
    }

    private static async Task StartServiceAsync()
    {
        var state = await GetServiceStateAsync();
        if (state != ServiceRunning)
        {
            await RunServiceCommandAsync("start");
        }

        await WaitForServiceStateAsync(ServiceRunning);
    }

    private static async Task WaitForServiceStateAsync(int expectedState)
    {
        var deadline = DateTime.UtcNow.AddSeconds(45);
        while (DateTime.UtcNow < deadline)
        {
            if (await GetServiceStateAsync() == expectedState)
            {
                return;
            }

            await Task.Delay(500);
        }

        throw new InvalidOperationException("El servicio InventarioAPI no alcanzó el estado esperado.");
    }

    private static async Task<(int ExitCode, string Output)> RunServiceCommandAsync(string action)
    {
        using var process = new Process
        {
            StartInfo = new ProcessStartInfo("sc.exe")
            {
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            }
        };
        process.StartInfo.ArgumentList.Add(action);
        process.StartInfo.ArgumentList.Add(ServiceName);

        if (!process.Start())
        {
            throw new InvalidOperationException("No se pudo controlar el servicio InventarioAPI.");
        }

        var outputTask = process.StandardOutput.ReadToEndAsync();
        var errorTask = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        var output = await outputTask;
        var error = await errorTask;
        return (process.ExitCode, $"{output}{error}");
    }

    private static async Task VerifyHealthAsync(int port, Action<string> log)
    {
        log($"Comprobando http://localhost:{port}/health (consulta de lectura)...");
        var deadline = DateTime.UtcNow.AddSeconds(60);
        while (DateTime.UtcNow < deadline)
        {
            try
            {
                using var response = await HttpClient.GetAsync($"http://localhost:{port}/health");
                var content = await response.Content.ReadAsStringAsync();
                if (response.IsSuccessStatusCode)
                {
                    using var health = JsonDocument.Parse(content);
                    if (health.RootElement.TryGetProperty("ok", out var ok)
                        && ok.ValueKind == JsonValueKind.True
                        && health.RootElement.TryGetProperty("db", out var database)
                        && database.GetString() == "up")
                    {
                        return;
                    }
                }
            }
            catch (Exception exception) when (
                exception is HttpRequestException
                or TaskCanceledException
                or JsonException
                or WebException)
            {
            }

            await Task.Delay(1000);
        }

        throw new InvalidOperationException(
            "El servicio inició, pero /health no confirmó la conexión con la base de datos en 60 segundos.");
    }
}
