*! rtmtools.ado  version 0.6.0  25oct2026  rtmtools
*! Entry point: rtmtools input ... (= rtminput), rtmtools setup ... (= rtmtools_setup),
*! rtmtools dashboard ... (= rtmtools_dashboard); rtmtools alone opens the overview help.
program define rtmtools, rclass
    version 16
    gettoken sub rest : 0, parse(" ,")
    local sub = lower("`sub'")
    if "`sub'" == "" {
        help rtmtools
        exit
    }
    if "`sub'" == "input" {
        rtminput `rest'
        return add
        exit
    }
    if "`sub'" == "setup" {
        rtmtools_setup `rest'
        exit
    }
    if "`sub'" == "dashboard" {
        rtmtools_dashboard `rest'
        exit
    }
    di as err "rtmtools: unknown subcommand `sub' (input, setup, dashboard; or help rtmtools)"
    exit 198
end
