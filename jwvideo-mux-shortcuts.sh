#!/bin/bash
# jwvideo-mux-shortcuts.sh
#
# Short commands for the jwvideo-mux workflows used most often against SCE-layout local
# video libraries. Source this from your shell rc:
#
#   source /Users/maj/dig/maj-scripts-vibe/jwvideo-mux-shortcuts.sh
#
# Layout these assume (matches "SCE Instructor/SCE Media/<unit>/"):
#
#   <unit root>/E/<video>.mp4        <- reference/base language video (run commands from in here)
#   <unit root>/TG/, HV/, CV/, SA/   <- sibling per-language folders, auto-discovered by filename
#   <unit root>/<video>/             <- adaptive-library output, a SIBLING of E/, TG/, ... (not
#                                        inside E/), named after the video itself, no suffix.
#                                        Only created when there's actually something to split --
#                                        a video with no real per-language differences instead
#                                        gets one ordinary .mkv written straight into <unit root>.
#   <unit root>/Play <Language> - <video title>.command   <- launchers, at the unit root by default
#
# Every function below must be run with cwd = the base-language folder (usually E/), and takes
# the video filename (not full path) as its first argument. langs defaults to E,TG,CV,HV,SA --
# pass a second argument to override (e.g. "E,TG,HV" if this unit has no CV/SA source).

JWVIDEOMUX="/Users/maj/dig/maj-scripts-vibe/jwvideo-mux"
JWVM_DEFAULT_LANGS="E,TG,CV,HV,SA"
JWVM_LANG_DIR_NAMES="E TG HV CV SA F S"  # never treated as a library folder by jwvm-relang's glob

# Human-audited ground truth for the whole SCE Media corpus (built 2026-07-28, see the file's own
# header). This is the authoritative correction layer -- e.g. it's the only thing that tells
# jwvideo-mux "iut_E_r720P (Integrity Under Trial)"'s HV/TG really do differ (a name plate/title
# card) even though the automatic detector alone reports them merely `review_recommended`, or that
# "mwbv_E_201708_04..." is `whole_video_same` despite an encoding-only SSIM dip. Applied
# automatically below whenever the file exists so a plain jwvm-build can't accidentally skip it
# (a real mistake made once already: an early manual rebuild without this flag mis-classified a
# confirmed real difference as "nothing to adapt"). Falls back to no override silently if this path
# doesn't exist (e.g. these shortcuts sourced somewhere outside this corpus).
JWVM_GROUND_TRUTH="/Users/maj/Theoskratos/Field Instructor/SCE Instructor/SCE Media/_localization-audit/ground-truth.toml"

_jwvm_check_cwd() {
    if [[ ! -f "$1" ]]; then
        echo "jwvm: '$1' not found in $(pwd) -- run this from inside the base-language folder (e.g. E/)." >&2
        return 1
    fi
}

# Populates the caller's own "overrides" array (bash has no return-an-array, so this takes the
# array's NAME and fills it via nameref) -- needed because JWVM_GROUND_TRUTH's path has spaces in
# it, and passing that around as a plain string would break under word-splitting.
_jwvm_overrides_into() {
    local -n _out="$1"
    _out=()
    [[ -f "$JWVM_GROUND_TRUTH" ]] && _out=(--manual-overrides "$JWVM_GROUND_TRUTH")
}

# Read-only: report exact-reuse and localized-difference candidates. Never writes or deletes
# anything. Run this FIRST on a new video to see what --adaptive-mpv-library would do.
jwvm-plan() {
    local video="$1" langs="${2:-$JWVM_DEFAULT_LANGS}"
    _jwvm_check_cwd "$video" || return 1
    local overrides=(); _jwvm_overrides_into overrides
    "$JWVIDEOMUX" "$video" -v "$langs" -o .. --analyze-video-variants "${overrides[@]}"
}

# Build (or rebuild) the adaptive mpv library: shared common video + per-language localized
# segments/audio/subs/EDL/manifest + "Play <Language> - <title>.command" launchers at the unit
# root. If the video turns out to have no real per-language differences, jwvideo-mux itself falls
# back to one ordinary shared-video MKV written straight into the unit root -- no folder, no EDL.
# Automatically applies the corpus ground-truth file (see JWVM_GROUND_TRUTH above) when present.
# NOTE: this does not clear a pre-existing library folder first -- if segment boundaries shift
# (e.g. after adding/removing a language) stale files can be left behind. Use jwvm-relang below
# when you're changing the language set on a library you've already built once.
# Pass extra_flags for e.g. --normalize-mismatched-aspect (crop/re-encode a mismatched-resolution
# language's short localized clips to match the reference instead of letting mpv resize mid-play).
# extra_flags is split on whitespace, so it must not itself contain a space-bearing value (use
# jwvideo-mux directly for that, as with a custom --manual-overrides path).
jwvm-build() {
    local video="$1" langs="${2:-$JWVM_DEFAULT_LANGS}" extra_flags="$3"
    _jwvm_check_cwd "$video" || return 1
    local overrides=(); _jwvm_overrides_into overrides
    "$JWVIDEOMUX" "$video" -v "$langs" -o .. --adaptive-mpv-library --force "${overrides[@]}" $extra_flags
}

# Classic single-file mux: one MKV with every requested language as a selectable audio/subtitle
# track, no video-track deduplication. Use this for a video with no real per-language visual
# differences worth splitting out (jwvm-plan will tell you: all pairs exactly_same/visually_same) --
# though jwvm-build now does this automatically in that case, so you rarely need to reach for this
# directly.
jwvm-mux() {
    local video="$1" langs="${2:-$JWVM_DEFAULT_LANGS}"
    _jwvm_check_cwd "$video" || return 1
    "$JWVIDEOMUX" "$video" -v E -a "$langs" -o .. --force
}

# Add or remove a language from an already-built adaptive library. jwvideo-mux has no incremental
# update mode -- changing the language set can shift every segment boundary, so this finds the
# existing library folder (named after the video, no suffix), shows it to you, asks to confirm,
# deletes it, then rebuilds from scratch with the new language list (same as jwvm-build).
jwvm-relang() {
    local video="$1" langs="$2" extra_flags="$3"
    if [[ -z "$langs" ]]; then
        echo "usage: jwvm-relang <video.mp4> <new-comma-separated-langs> [extra jwvideo-mux flags]" >&2
        return 1
    fi
    _jwvm_check_cwd "$video" || return 1

    local docid="${video%%_*}"
    local unit_root
    unit_root="$(cd .. && pwd)"
    local candidates=("$unit_root/${docid}"*) matches=()
    local c base is_lang_dir lang
    for c in "${candidates[@]}"; do
        [[ -d "$c" ]] || continue
        base="$(basename "$c")"
        is_lang_dir=0
        for lang in $JWVM_LANG_DIR_NAMES; do
            [[ "$base" == "$lang" ]] && is_lang_dir=1 && break
        done
        [[ "$is_lang_dir" == 0 ]] && matches+=("$c")
    done

    if [[ ${#matches[@]} -eq 0 ]]; then
        echo "jwvm: no existing '${docid}*' library folder under $unit_root -- if this video was built with no localized differences it may just be a single .mkv there already; jwvm-build will overwrite it directly." >&2
        return 1
    fi
    if [[ ${#matches[@]} -gt 1 ]]; then
        echo "jwvm: more than one match, refusing to guess:" >&2
        printf '  %s\n' "${matches[@]}" >&2
        return 1
    fi

    echo "About to delete and rebuild:"
    echo "  ${matches[0]}"
    echo "  new language list: $langs"
    read -r -p "Proceed? [y/N] " ans
    [[ "$ans" == "y" || "$ans" == "yes" ]] || { echo "Aborted."; return 1; }

    rm -rf "${matches[0]}"
    jwvm-build "$video" "$langs" "$extra_flags"
}

jwvm-help() {
    cat <<'EOF'
jwvideo-mux shortcuts (run from inside the base-language folder, e.g. E/):

  jwvm-plan   <video.mp4> [langs]                  read-only variant report, no writes
  jwvm-build  <video.mp4> [langs] [extra flags]     build/overwrite the adaptive mpv library
                                                     (auto-falls-back to one plain MKV when
                                                     there's nothing to adapt); pass
                                                     "--normalize-mismatched-aspect" as extra
                                                     flags to crop/reencode a mismatched-aspect
                                                     language's clips to match the reference
  jwvm-mux    <video.mp4> [langs]                   classic single-file multi-track MKV
  jwvm-relang <video.mp4> <new-langs> [extra flags] change the language set on an existing
                                                     library (deletes + rebuilds, confirms first)

langs defaults to: E,TG,CV,HV,SA
EOF
}
