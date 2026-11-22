load("@rules_cc//cc:defs.bzl", "cc_binary")

def strict_cc_binary(name, srcs, deps = [], **kwargs):
    """Macro that wraps cc_binary with strict C++20 compiler flags."""
    default_copts = ["-std=c++20", "-Wall", "-Wextra", "-O2"]
    user_copts = kwargs.pop("copts", [])

    cc_binary(
        name = name,
        srcs = srcs,
        deps = deps,
        copts = default_copts + user_copts,
        **kwargs
    )

def _binary_info_impl(ctx):
    binary = ctx.file.target_bin
    out_report = ctx.actions.declare_file(ctx.label.name + "_report.txt")

    ctx.actions.run_shell(
        inputs = [binary],
        outputs = [out_report],
        command = "file -b '%s' > '%s'" % (binary.path, out_report.path),
        mnemonic = "InspectBinaryFormat",
        progress_message = "Inspecting binary format for %s" % binary.short_path,
    )

    return [DefaultInfo(files = depset([out_report]))]

verify_binary_format = rule(
    implementation = _binary_info_impl,
    attrs = {
        "target_bin": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
    },
)
