# ==============================================================================
# Bazel Multi-Platform Transition & Release Bundle Rule
# ==============================================================================

def _multi_platform_transition_impl(settings, attr):
    """1:N Split Transition:
    Takes a single incoming dependency (`binary`) and forks the build graph into
    three separate configurations (macOS arm64, Linux x86_64, Linux arm64).

    Returning a dictionary of {config_key: {flag: value}} tells Bazel to build
    the target once for each entry in the dictionary.
    """
    return {
        "macos_arm64": {
            "//command_line_option:platforms": str(attr.macos_platform),
        },
        "linux_x86_64": {
            "//command_line_option:platforms": str(attr.linux_x86_64_platform),
        },
        "linux_arm64": {
            "//command_line_option:platforms": str(attr.linux_arm64_platform),
        },
    }

# Define the split transition object
_multi_platform_transition = transition(
    implementation = _multi_platform_transition_impl,
    inputs = [],  # No existing CLI flags needed to compute the target platforms
    outputs = ["//command_line_option:platforms"],  # Flag overridden per split branch
)

def _release_bundle_impl(ctx):
    """Rule implementation that collects binaries from all 3 transitioned platforms,
    organizes them into clean OS/arch folders, and packs a reproducible .tar.gz.
    """
    # Because `binary` uses a 1:N split transition, `ctx.split_attr.binary` is a
    # dictionary keyed by the branch names returned in `_multi_platform_transition_impl`:
    #   {"macos_arm64": Target, "linux_x86_64": Target, "linux_arm64": Target}
    staged_files = []
    manifest_lines = []

    for platform_key, target in ctx.split_attr.binary.items():
        # Extract the compiled executable from each platform branch
        bin_file = target[DefaultInfo].files_to_run.executable

        # Copy each binary into a clean staging path inside bazel-out:
        # e.g., release_staging/linux_x86_64/hello_world
        staged = ctx.actions.declare_file("release_staging/%s/%s" % (platform_key, bin_file.basename))
        ctx.actions.run_shell(
            inputs = [bin_file],
            outputs = [staged],
            command = "cp -f '%s' '%s' && chmod 755 '%s'" % (bin_file.path, staged.path, staged.path),
            mnemonic = "StagePlatformBinary",
        )
        staged_files.append(staged)
        manifest_lines.append("%s -> %s/hello_world" % (platform_key, platform_key))

    # Create a manifest file listing all bundled architectures
    manifest = ctx.actions.declare_file("release_staging/MANIFEST.txt")
    ctx.actions.write(
        output = manifest,
        content = "Multi-Architecture Release Bundle\n" + "\n".join(sorted(manifest_lines)) + "\n",
    )
    staged_files.append(manifest)

    # Package all staged binaries + manifest into one single .tar.gz archive
    out_tar = ctx.outputs.out
    staging_root = manifest.dirname  # Points to .../release_staging

    ctx.actions.run_shell(
        inputs = staged_files,
        outputs = [out_tar],
        # Use tar -C to strip long bazel-out/k8-fastbuild/... prefixes inside the archive
        command = "tar -czf '%s' -C '%s' ." % (out_tar.path, staging_root),
        mnemonic = "PackageReleaseTarball",
        progress_message = "Creating multi-platform release tarball %s" % out_tar.short_path,
    )

    return [DefaultInfo(files = depset([out_tar]))]

release_bundle = rule(
    implementation = _release_bundle_impl,
    attrs = {
        # `cfg = _multi_platform_transition` triggers the 1:N split transition on `binary`
        "binary": attr.label(
            cfg = _multi_platform_transition,
            mandatory = True,
        ),
        # Platform labels passed from BUILD.bazel so transition stays decoupled from hardcoded paths
        "macos_platform": attr.label(mandatory = True),
        "linux_x86_64_platform": attr.label(mandatory = True),
        "linux_arm64_platform": attr.label(mandatory = True),
        # Required Bazel allowlist whenever a rule attaches a Starlark transition
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    outputs = {
        "out": "%{name}.tar.gz",
    },
)
