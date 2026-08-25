using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.CompilerServices;
using UnityEditor;
using UnityEditor.Build;
using PackageManagerPackageInfo = UnityEditor.PackageManager.PackageInfo;
using UnityEngine;

namespace Magi.InkTools.Editor
{
    /// <summary>
    /// CP9f Slice B1 — the SINGLE WRITER of the INKTOOLS_IFLOAT_HALF synchronized pair:
    /// (1) the generated HLSL include (compile-time define for compute shaders), and
    /// (2) the C# Standalone scripting define (Unity C# defines do not reach compute shaders).
    ///
    /// This is the only supported way to change ifloat storage mode. B1 manages Standalone ONLY; iOS/Android
    /// are deferred (B3) and deliberately left at float/OFF — the safe default protected by the particle
    /// layout guard. Flipping to half is EXPERIMENTAL: it changes the C#-side iparticle stride to 28 bytes,
    /// which the SimulationResources guard rejects at runtime until Slice B2 adds half-aware mirrors/stride.
    /// The committed repository state is float/OFF; use "Set Float (default)" to restore it after any test.
    /// </summary>
    public static class InkToolsIFloatModeToggle
    {
        public const string Define = "INKTOOLS_IFLOAT_HALF";

        // AssetDatabase path in a package-consumer project (e.g. Inkling). In the InkTools-own project the
        // same file is under Assets/. Never do filesystem IO on this virtual path directly — resolve it via
        // ResolveGeneratedIncludeFullPath().
        public const string GeneratedIncludeAssetPath =
            "Packages/com.inktools.core/Compute/InkToolsConfig.generated.hlsl";

        // B1 manages Standalone only. Extended to iOS/Android in B3 once hardware-validated.
        private static readonly NamedBuildTarget[] ManagedTargets = { NamedBuildTarget.Standalone };

        [MenuItem("InkTools/ifloat Mode/Set Half (experimental)")]
        public static void SetHalf() => SetMode(true);

        [MenuItem("InkTools/ifloat Mode/Set Float (default)")]
        public static void SetFloat() => SetMode(false);

        [MenuItem("InkTools/ifloat Mode/Log Current State")]
        public static void LogState()
        {
            Debug.Log($"[InkToolsIFloatMode] generatedIncludeModeHalf={ReadGeneratedModeHalf()}, " +
                      $"standaloneDefineHalf={HasStandaloneDefine()}, path={ResolveGeneratedIncludeFullPath()}");
        }

        /// <summary>Atomically set both sides of the pair, then reimport so the change takes effect.</summary>
        public static void SetMode(bool half)
        {
            // The C# define only affects compilation of the ACTIVE build target. B1 writes Standalone, so
            // warn if the active target is not Standalone (otherwise the C# assemblies won't pick up the flip).
            if (BuildPipeline.GetBuildTargetGroup(EditorUserBuildSettings.activeBuildTarget)
                != BuildTargetGroup.Standalone)
            {
                Debug.LogWarning("[InkToolsIFloatMode] Active build target is not Standalone. B1 toggles the " +
                    "Standalone scripting define only; switch the active target to Standalone (Windows) so the " +
                    "C# assemblies recompile with INKTOOLS_IFLOAT_HALF.");
            }

            WriteGeneratedInclude(half);
            SetStandaloneDefine(half);
            AssetDatabase.ImportAsset(GeneratedIncludeAssetPath, ImportAssetOptions.ForceUpdate);
            ReimportComputeShaders();
            AssetDatabase.Refresh();
            Debug.Log($"[InkToolsIFloatMode] Mode set to {(half ? "HALF (experimental)" : "FLOAT (default)")} " +
                      "for Standalone only; iOS/Android untouched (remain float).");
        }

        // ---- path resolution ---------------------------------------------------------------------------

        /// <summary>
        /// Map the generated include to a real filesystem path that works in BOTH the package-consumer
        /// project and the InkTools-own project. Prefers the UPM resolvedPath; falls back to resolving the
        /// file as a sibling of this script (CallerFilePath gives the real on-disk path the assembly was
        /// compiled from, which for a local package is the actual InkTools source).
        /// </summary>
        public static string ResolveGeneratedIncludeFullPath()
        {
            var pkg = PackageManagerPackageInfo.FindForAssetPath(GeneratedIncludeAssetPath);
            if (pkg != null && !string.IsNullOrEmpty(pkg.resolvedPath))
            {
                string prefix = "Packages/" + pkg.name + "/";
                if (GeneratedIncludeAssetPath.StartsWith(prefix, StringComparison.Ordinal))
                    return Path.GetFullPath(Path.Combine(pkg.resolvedPath,
                        GeneratedIncludeAssetPath.Substring(prefix.Length)));
            }

            // Fallback: <Core>/Editor/InkToolsIFloatModeToggle.cs -> <Core>/Compute/InkToolsConfig.generated.hlsl
            string editorDir = Path.GetDirectoryName(ThisFilePath());
            return Path.GetFullPath(Path.Combine(editorDir, "..", "Compute", "InkToolsConfig.generated.hlsl"));
        }

        private static string ThisFilePath([CallerFilePath] string path = null) => path;

        // ---- generated include (single writer) ---------------------------------------------------------

        /// <summary>Rewrite the generated include with an explicit 0/1 mode. LF newlines to match the
        /// committed file byte-for-byte so a half->float round-trip leaves no diff. Emits an authoritative
        /// #undef so the 0/1 marker is the only shader-side source of truth.</summary>
        public static void WriteGeneratedInclude(bool half)
        {
            int mode = half ? 1 : 0;
            string[] lines =
            {
                "// AUTO-GENERATED by InkToolsIFloatModeToggle — do not edit by hand.",
                "// Single-writer half/float flag for the InkTools ifloat switch (CP9f Slice B1).",
                "// Flip only via InkTools > ifloat Mode, which also sets the C# Standalone scripting define.",
                "#ifndef INKTOOLS_CONFIG_GENERATED_HLSL",
                "#define INKTOOLS_CONFIG_GENERATED_HLSL",
                "",
                $"#define INKTOOLS_IFLOAT_MODE_HALF {mode}   // 0 = float (default), 1 = half",
                "",
                "// Authoritative shader-side source of truth: clear any preexisting INKTOOLS_IFLOAT_HALF (injected globally",
                "// or by an earlier include) so the 0/1 marker above is the ONLY thing that selects half vs float.",
                "#undef INKTOOLS_IFLOAT_HALF",
                "#if INKTOOLS_IFLOAT_MODE_HALF",
                "#define INKTOOLS_IFLOAT_HALF",
                "#endif",
                "",
                "#endif // INKTOOLS_CONFIG_GENERATED_HLSL",
                ""
            };
            File.WriteAllText(ResolveGeneratedIncludeFullPath(), string.Join("\n", lines));
        }

        /// <summary>Parse INKTOOLS_IFLOAT_MODE_HALF from the generated include. Returns 0/1, or -1 if the
        /// file is missing or the marker is unparseable (distinguishing OFF from corrupt/absent).</summary>
        public static int ReadGeneratedModeHalf()
        {
            string full = ResolveGeneratedIncludeFullPath();
            if (!File.Exists(full)) return -1;
            foreach (var raw in File.ReadAllLines(full))
            {
                string line = raw.Trim();
                if (line.StartsWith("#define INKTOOLS_IFLOAT_MODE_HALF", StringComparison.Ordinal))
                {
                    string[] parts = line.Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
                    // parts: [#define][INKTOOLS_IFLOAT_MODE_HALF][value]...
                    if (parts.Length >= 3 && int.TryParse(parts[2], out int v))
                        return v;
                }
            }
            return -1;
        }

        // ---- C# scripting define (Standalone only) -----------------------------------------------------

        public static bool HasStandaloneDefine()
        {
            string defs = PlayerSettings.GetScriptingDefineSymbols(NamedBuildTarget.Standalone);
            foreach (var d in defs.Split(';'))
                if (d.Trim() == Define) return true;
            return false;
        }

        private static void SetStandaloneDefine(bool enable)
        {
            foreach (var target in ManagedTargets)
            {
                string defs = PlayerSettings.GetScriptingDefineSymbols(target);
                var list = new List<string>(defs.Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries));
                bool present = list.Contains(Define);
                if (enable && !present) list.Add(Define);
                else if (!enable && present) list.RemoveAll(d => d == Define);
                PlayerSettings.SetScriptingDefineSymbols(target, string.Join(";", list));
            }
        }

        // ---- shader reimport ---------------------------------------------------------------------------

        /// <summary>Force-reimport compute shaders so the new compile-time define is applied. Best-effort:
        /// reimports every ComputeShader in the project (the particle/fluid kernels that include the shared
        /// type header are the ones that matter).</summary>
        private static void ReimportComputeShaders()
        {
            foreach (string guid in AssetDatabase.FindAssets("t:ComputeShader"))
            {
                string path = AssetDatabase.GUIDToAssetPath(guid);
                if (!string.IsNullOrEmpty(path))
                    AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceUpdate);
            }
        }
    }
}
