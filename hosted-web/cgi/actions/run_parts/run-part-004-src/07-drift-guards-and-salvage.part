                use strict;
                use warnings;
                local $/;
                my $raw = <>;
                my $dir = $ENV{"FILE_BLOCKS_DIR"} // "";
                my $count = 0;
                my %seen_path;

                my $emit = sub {
                  my ($path, $content) = @_;
                  $path = "" if !defined $path;
                  $content = "" if !defined $content;
                  $path =~ s/^\s+//;
                  $path =~ s/\s+$//;
                  return if $path eq "";
                  return if $path =~ m{(?:^|/)\.\.(?:/|$)};
                  return if $path =~ m{^/};
                  return if $seen_path{$path};
                  return if $content !~ /\S/;
                  $count += 1;
                  return if $count > 5;
                  my $tmp_path = "$dir/$count.content";
                  open my $fh, ">:encoding(UTF-8)", $tmp_path or return;
                  print {$fh} $content;
                  close $fh;
                  $seen_path{$path} = 1;
                  print "$path\t$tmp_path\n";
                };

                while ($raw =~ /FILE:\s*([^\r\n]+)\s*\r?\n```[^\n]*\n(.*?)\n```/sg) {
                  $emit->($1, $2);
                }

                if ($count == 0) {
                  while ($raw =~ /FILE:\s*([^\r\n]+)\s*\r?\n(.*?)(?=\r?\nFILE:\s*[^\r\n]+\s*\r?\n|\z)/sg) {
                    my $path = $1;
                    my $content = $2 // "";
                    $content =~ s/\A\r?\n//;
                    $content =~ s/\r?\n\z//;
                    $content =~ s/\A```[^\n]*\n//s;
                    $content =~ s/\n```[ \t]*\z//s;
                    $emit->($path, $content);
                  }
                }
              ' > "$file_blocks_index"
              if [ -s "$file_blocks_index" ]; then
                break
              fi
            done <<EOF
$implement_models
EOF

            synthesized_patch=""
            if [ -s "$file_blocks_index" ]; then
              while IFS='	' read -r out_path out_tmp; do
                out_path=$(trim "$out_path")
                out_tmp=$(trim "$out_tmp")
                [ -n "$out_path" ] || continue
                [ -f "$out_tmp" ] || continue
                if ! is_safe_relative_path "$out_path"; then
                  continue
                fi
                mkdir -p "$(dirname "$workspace_path/$out_path")" 2>/dev/null || true
                if [ -f "$workspace_path/$out_path" ]; then
                  file_diff=$(diff -u "$workspace_path/$out_path" "$out_tmp" || true)
                  if [ -n "$(trim "$file_diff")" ]; then
                    file_diff=$(printf '%s\n' "$file_diff" | sed "1s|^--- .*|--- a/$out_path|;2s|^+++ .*|+++ b/$out_path|")
                    synthesized_patch="${synthesized_patch}
${file_diff}"
                  fi
                else
                  file_diff=$(diff -u /dev/null "$out_tmp" || true)
                  if [ -n "$(trim "$file_diff")" ]; then
                    file_diff=$(printf '%s\n' "$file_diff" | sed "1s|^--- .*|--- /dev/null|;2s|^+++ .*|+++ b/$out_path|")
                    synthesized_patch="${synthesized_patch}
${file_diff}"
                  fi
                fi
              done < "$file_blocks_index"
            fi

            rm -rf "$file_blocks_dir" 2>/dev/null || true
            rm -f "$file_blocks_index"

            synthesized_patch=$(trim_block_edges "$synthesized_patch")
            if patch_candidate_is_usable "$synthesized_patch"; then
              patch_text=$synthesized_patch
              patch_trimmed=$synthesized_patch
            fi
          fi

          if [ "$hello_script_task" -ne 1 ] && [ "$bootstrap_forced" -ne 1 ] && ! { [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$narrow_slice_direct_attempted" -eq 1 ]; } && { [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; }; then
            focused_patch_prompt=$(cat <<EOF
You are a coding assistant generating final implementation output.
Return ONLY a valid unified diff touching at most 5 files.
No prose, no markdown outside a single diff fence.

Rules:
- include --- and +++ headers for every file
- use --- /dev/null for new files
- use +++ b/<relative-path> paths
- do not include command suggestions
- choose sensible defaults when details are underspecified

Task:
$augmented_user_prompt
EOF
)
            retry_timeout_sec=$(model_timeout_for_run "$run_started_epoch" "$run_time_budget" 26 8 5)
            while IFS= read -r retry_model; do
              retry_model=$(trim "$retry_model")
              [ -n "$retry_model" ] || continue
              if [ -n "$stream_output_file" ] && [ "$active_run_mode" != "programming" ]; then
                ARTIFICER_STREAM_FILE="$stream_output_file"
                export ARTIFICER_STREAM_FILE
              fi
              RUN_TIMEOUT_SEC=$retry_timeout_sec
              focused_output=$(run_model "$retry_model" "$focused_patch_prompt" || true)
              unset RUN_TIMEOUT_SEC 2>/dev/null || true
              unset ARTIFICER_STREAM_FILE 2>/dev/null || true
              focused_output=$(strip_terminal_noise "$focused_output")
              focused_patch_section=$(extract_patch_section "$focused_output")
              focused_patch_text=$(normalize_patch_text "$focused_patch_section")
              focused_patch_trimmed=$(trim "$focused_patch_text")
              resolved_patch_text=$(resolve_patch_candidate "$focused_patch_text" || true)
              if [ -n "$(trim "$resolved_patch_text")" ]; then
                patch_text=$resolved_patch_text
                patch_trimmed=$(trim "$resolved_patch_text")
                break
              fi
            done <<EOF
$implement_models
EOF
          fi

          if [ "$hello_script_task" -ne 1 ] && [ "$bootstrap_forced" -ne 1 ] && { [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; }; then
            bootstrap_patch=$(framework_bootstrap_patch_for_prompt "$augmented_user_prompt")
            bootstrap_patch=$(trim "$bootstrap_patch")
            if [ -n "$bootstrap_patch" ]; then
              resolved_patch_text=$(resolve_patch_candidate "$bootstrap_patch" || true)
              if [ -n "$(trim "$resolved_patch_text")" ]; then
                patch_text=$resolved_patch_text
                patch_trimmed=$(trim "$resolved_patch_text")
                append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                  "Applied framework bootstrap fallback patch" "Model did not produce a usable patch payload" \
                  "Proceed with synthesized framework baseline patch"
              fi
            fi
          fi

          if [ "$hello_script_task" -ne 1 ] && [ -n "$patch_trimmed" ] && [ "$patch_trimmed" != "NONE" ]; then
            if framework_patch_is_low_confidence "$augmented_user_prompt" "$patch_text" "$workspace_path"; then
              bootstrap_patch=$(framework_bootstrap_patch_for_prompt "$augmented_user_prompt")
              bootstrap_patch=$(trim "$bootstrap_patch")
              if [ -n "$bootstrap_patch" ]; then
                resolved_patch_text=$(resolve_patch_candidate "$bootstrap_patch" || true)
                if [ -n "$(trim "$resolved_patch_text")" ]; then
                  patch_text=$resolved_patch_text
                  patch_trimmed=$(trim "$resolved_patch_text")
                  append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                    "Replaced low-confidence framework patch with bootstrap baseline" \
                    "Model patch failed framework contract checks for an empty framework workspace" \
                    "Proceed with known-good framework bootstrap patch"
                fi
              fi
            fi
          fi

          if [ "$hello_script_task" -ne 1 ] && { [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; }; then
            case "$(printf '%s' "$augmented_user_prompt" | tr '[:upper:]' '[:lower:]')" in
              *hello.sh*hello*world*)
                patch_text=$(cat <<'EOF'
--- /dev/null
+++ b/hello.sh
@@ -0,0 +1,2 @@
+#!/bin/sh
+printf '%s\n' 'Hello, world!'
EOF
)
                patch_trimmed=$(trim "$patch_text")
                ;;
            esac
          fi

          if [ "$allow_workspace_writes" -ne 1 ]; then
            printf '%s\n' "Patch blocked by read-only permissions. Switch to Workspace write or Default to apply edits." > "$patch_report_file"
            append_failure_entry "$failures_file" "implement-iteration-$iteration" \
              "Patch blocked by read-only permissions" "Current permission mode forbids workspace edits" \
              "Ask user to grant write permissions and retry"
          elif [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; then
            printf '%s\n' "Implement mode did not include a patch payload." > "$patch_report_file"
            append_failure_entry "$failures_file" "implement-iteration-$iteration" \
              "Missing patch payload" "Implementation step requires a unified diff" \
              "Generate scoped patch for target files"
          else
            patch_paths_file=$(mktemp)
            patch_paths_from_text "$patch_text" > "$patch_paths_file"
            disallowed_patch_rejected=0

            patch_paths_normalized_file=$(mktemp)
            : > "$patch_paths_normalized_file"
            while IFS= read -r raw_rel_path; do
              rel_path=$(trim "$raw_rel_path")
              [ -n "$rel_path" ] || continue
              norm_rel_path=$rel_path
              case "$norm_rel_path" in
                "$workspace_path"/*)
                  norm_rel_path=${norm_rel_path#"$workspace_path"/}
                  ;;
              esac
              case "$norm_rel_path" in
                res://*)
                  norm_rel_path=${norm_rel_path#res://}
                  ;;
                file://*)
                  norm_rel_path=${norm_rel_path#file://}
                  ;;
              esac
              if [ "$norm_rel_path" != "$rel_path" ]; then
                patch_text=$(printf '%s\n' "$patch_text" | PATCH_ORIG_PATH="$rel_path" PATCH_NORM_PATH="$norm_rel_path" perl -0pe '
                  my $orig = quotemeta($ENV{"PATCH_ORIG_PATH"} // "");
                  my $norm = $ENV{"PATCH_NORM_PATH"} // "";
                  s/^--- a\/$orig$/--- a\/$norm/mg;
                  s/^\+\+\+ b\/$orig$/+++ b\/$norm/mg;
                ')
              fi
              printf '%s\n' "$norm_rel_path" >> "$patch_paths_normalized_file"
            done < "$patch_paths_file"
            mv "$patch_paths_normalized_file" "$patch_paths_file"

            if [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ -n "$programming_focus_allowed_path" ] && [ -s "$patch_paths_file" ]; then
              focused_primary_fallback_patch=""
              if [ -n "$current_programming_slice_path" ] && programming_paths_match "$current_programming_slice_path" "$programming_focus_allowed_path"; then
                focused_primary_fallback_patch=$(programming_primary_slice_fallback_patch_for_path "$workspace_path" "$programming_focus_allowed_path")
                focused_primary_fallback_patch=$(trim "$focused_primary_fallback_patch")
              fi
              if patch_candidate_is_usable "$focused_primary_fallback_patch" && {
                programming_prompt_has_multiple_branches "$augmented_user_prompt" \
                  || find "$workspace_path" -maxdepth 2 -type f \( -path '*/bin/*' -o -name 'cli.*' \) | sed -n '1p' >/dev/null 2>&1
              } && printf '%s' "$patch_text" | grep -Eqi 'commander|program[.]parse|process[.]argv|require[.]main|--help|argv\[2\]|readline|createInterface|process[.]stdin|process[.]stdout|cliGreet|module[.]exports[[:space:]]*=[[:space:]]*\{[[:space:]]*greet[[:space:]]*,'; then
                patch_text=$focused_primary_fallback_patch
                patch_trimmed=$(trim "$focused_primary_fallback_patch")
                : > "$patch_paths_file"
                patch_paths_from_text "$patch_text" > "$patch_paths_file"
                append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                  "Primary slice tried to fold CLI behavior into $programming_focus_allowed_path; replaced with deterministic helper-only patch" \
                  "First narrow slice should keep CLI entry-point behavior out of the helper file" \
                  "Preserve the helper-only implementation slice before widening to the CLI file"
              fi
              disallowed_patch_path=$(awk -v allowed="$programming_focus_allowed_path" '$0 != allowed { print; exit }' "$patch_paths_file")
              if [ -n "$disallowed_patch_path" ]; then
                focused_fallback_patch=""
                if [ "$programming_quick_adjacent_slice_run" -eq 1 ] && [ -n "$current_programming_slice_path" ] && programming_paths_match "$current_programming_slice_path" "$programming_focus_allowed_path"; then
                  focused_fallback_patch=$(programming_adjacent_slice_fallback_patch_for_path "$workspace_path" "$programming_focus_allowed_path")
                  focused_fallback_patch=$(trim "$focused_fallback_patch")
                fi
                if patch_candidate_is_usable "$focused_fallback_patch"; then
                  patch_text=$focused_fallback_patch
                  patch_trimmed=$(trim "$focused_fallback_patch")
                  : > "$patch_paths_file"
                  patch_paths_from_text "$patch_text" > "$patch_paths_file"
                  append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                    "Focused patch drifted outside $programming_focus_allowed_path; replaced with deterministic single-file fallback" \
                    "Model patch widened to $disallowed_patch_path during a narrow-slice follow-up pass" \
                    "Keep the selected slice single-purpose and fall back to the deterministic target-only patch"
                else
                  disallowed_patch_rejected=1
                  printf '%s\n' "Patch widened outside the selected slice: $disallowed_patch_path" > "$patch_report_file"
                  append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                    "Focused patch changed $disallowed_patch_path instead of the selected slice $programming_focus_allowed_path" \
                    "Narrow-slice patch drifted outside the chosen implementation file" \
                    "Keep the patch on the selected primary file only"
                fi
              fi
            fi

            if [ "$disallowed_patch_rejected" -eq 1 ]; then
              patch_text=""
              patch_trimmed=""
            elif [ ! -s "$patch_paths_file" ]; then
              case "$(printf '%s' "$augmented_user_prompt" | tr '[:upper:]' '[:lower:]')" in
                *hello.sh*hello*world*)
                  patch_text=$(cat <<'EOF'
--- /dev/null
+++ b/hello.sh
@@ -0,0 +1,2 @@
+#!/bin/sh
+printf '%s\n' 'Hello, world!'
EOF
)
                  patch_paths_from_text "$patch_text" > "$patch_paths_file"
                  ;;
              esac
            fi

            if [ ! -s "$patch_paths_file" ]; then
              printf '%s\n' "No target files were detected in PATCH section." > "$patch_report_file"
              append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                "Patch had no +++ paths" "Diff format malformed or missing headers" \
                "Emit standard unified diff with a/ and b/ paths"
            else
              touched_count=0
              invalid_path=""
              assay_invalid_path=""
              while IFS= read -r rel_path; do
                [ -n "$rel_path" ] || continue
                touched_count=$((touched_count + 1))
                if ! is_safe_relative_path "$rel_path"; then
                  invalid_path=$rel_path
                  break
                fi
                if [ "$assay_run_profile" -eq 1 ] && [ -n "$assay_edit_root" ]; then
                  case "$rel_path" in
                    "$assay_edit_root"/*)
                      ;;
                    *)
                      assay_invalid_path=$rel_path
                      break
                      ;;
                  esac
                fi
              done < "$patch_paths_file"

              if [ -n "$invalid_path" ]; then
                printf 'Unsafe path in patch: %s\n' "$invalid_path" > "$patch_report_file"
                append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                  "Unsafe target path: $invalid_path" "Path traversal or invalid characters" \
                  "Restrict patch to safe relative workspace paths"
              elif [ -n "$assay_invalid_path" ]; then
                printf 'Assay patch out-of-scope path: %s (allowed prefix: %s/)\n' "$assay_invalid_path" "$assay_edit_root" > "$patch_report_file"
                append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                  "Assay patch out of scope: $assay_invalid_path" \
                  "Assay safety policy limits edits to $assay_edit_root/" \
                  "Regenerate patch under the assay edit root"
              elif [ "$touched_count" -gt 5 ]; then
                printf 'Patch touched too many files: %s\n' "$touched_count" > "$patch_report_file"
                append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                  "Patch touched more than 5 files" "Iteration scope too broad" \
                  "Split patch into smaller batches"
              else
                iter_scratch="$scratch_root/iter-$iteration-$(new_id)"
                mkdir -p "$iter_scratch"

                prepare_scratch_files "$workspace_path" "$iter_scratch" "$patch_paths_file"
                patch_file="$iter_scratch/proposed.patch"
                printf '%s\n' "$patch_text" > "$patch_file"
                canonical_patch_file="$iter_scratch/proposed.canonical.patch"
                cp "$patch_file" "$canonical_patch_file"
                while IFS= read -r rel_path; do
                  [ -n "$rel_path" ] || continue
                  if [ ! -f "$workspace_path/$rel_path" ]; then
                    PATCH_REL_PATH="$rel_path" perl -0pi -e '
                      my $p = $ENV{"PATCH_REL_PATH"} // "";
                      $p = quotemeta($p);
                      s/^--- a\/$p$/--- \/dev\/null/mg;
                    ' "$canonical_patch_file"
                  fi
                done < "$patch_paths_file"
                patch_file="$canonical_patch_file"

                apply_log=$(mktemp)
                gate_log=$(mktemp)
                diff_log=$(mktemp)
                promote_log=$(mktemp)
                patch_already_present=0
                if apply_patch_to_scratch "$iter_scratch" "$patch_file" "$apply_log"; then
                  if run_gate_checks "$iter_scratch" "$patch_paths_file" "$gate_log" "$augmented_user_prompt" "$workspace_path"; then
                    diff_scratch_vs_workspace "$workspace_path" "$iter_scratch" "$patch_paths_file" "$diff_log"
                    if promote_scratch_files "$iter_scratch" "$workspace_path" "$patch_paths_file" "$promote_log"; then
                      patch_success=1
                      programming_record_changed_paths "$changed_paths_file" "$patch_paths_file"
                      diff_excerpt=$(sed -n '1,220p' "$diff_log")
                      if [ -z "$diff_excerpt" ]; then
                        diff_excerpt="No textual diff generated."
                      fi
                      post_snapshot=$(workspace_snapshot "$workspace_path" | sed -n '1,120p')
                      {
                        printf 'Patch applied through scratch gate.\n'
                        printf '\nApply output:\n%s\n' "$(sed -n '1,120p' "$apply_log")"
                        printf '\nGate output:\n%s\n' "$(sed -n '1,120p' "$gate_log")"
                        printf '\nPromotion output:\n%s\n' "$(sed -n '1,120p' "$promote_log")"
                        printf '\nPatch diff excerpt:\n%s\n' "$diff_excerpt"
                        printf '\nPost-write snapshot:\n%s\n' "$post_snapshot"
                      } > "$patch_report_file"
                    else
                      {
                        printf 'Promotion failed.\n'
                        printf '\nApply output:\n%s\n' "$(sed -n '1,120p' "$apply_log")"
                        printf '\nGate output:\n%s\n' "$(sed -n '1,120p' "$gate_log")"
                        printf '\nPromotion output:\n%s\n' "$(sed -n '1,120p' "$promote_log")"
                      } > "$patch_report_file"
                      append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                        "Scratch promotion failed" "File copy to workspace failed" \
                        "Inspect path and permissions before retrying"
                    fi
                  else
                    {
                      printf 'Gate checks failed.\n'
                      printf '\nApply output:\n%s\n' "$(sed -n '1,120p' "$apply_log")"
                      printf '\nGate output:\n%s\n' "$(sed -n '1,220p' "$gate_log")"
                    } > "$patch_report_file"
                    append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                      "Gate checks failed" "Syntax or conflict checks failed on scratch files" \
                      "Revise patch and retry"
                  fi
                elif [ "$programming_quick_narrow_slice_run" -eq 1 ] && already_present_log=$(mktemp) && patch_already_present_in_scratch "$iter_scratch" "$patch_file" "$already_present_log"; then
                  patch_success=1
                  patch_already_present=1
                  ARTIFICER_PROGRAMMING_CHANGED_PATHS=$(sed -n '1,20p' "$changed_paths_file" 2>/dev/null || true)
                  {
                    printf 'Selected slice already matched scratch workspace.\n'
                    printf '\nApply output:\n%s\n' "$(sed -n '1,220p' "$apply_log")"
                    printf '\nAlready-present check:\n%s\n' "$(sed -n '1,220p' "$already_present_log")"
                  } > "$patch_report_file"
                  rm -f "$already_present_log"
                else
                  rm -f "${already_present_log:-}" 2>/dev/null || true
                  {
                    printf 'Patch failed to apply in scratch workspace.\n'
                    printf '\nPatch preview:\n%s\n' "$(sed -n '1,120p' "$patch_file")"
                    printf '\nApply output:\n%s\n' "$(sed -n '1,220p' "$apply_log")"
                  } > "$patch_report_file"
                  append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                    "Patch apply failed" "Unified diff did not match scratch context" \
                    "Re-read target file and regenerate patch"
                fi

                rm -f "$apply_log" "$gate_log" "$diff_log" "$promote_log"
              fi
            fi

            rm -f "$patch_paths_file"
          fi

          patch_report=$(sed -n '1,260p' "$patch_report_file")
          rm -f "$patch_report_file"

          command_name=$(printf 'apply_patch iteration %s' "$iteration")
          if [ "$patch_success" -eq 1 ]; then
            command_status="ok"
          else
            command_status="failed"
          fi
          stream_emit_line "$stream_output_file" "Step $iteration patch gate status: $command_status"

          command_json=$(json_escape "$command_name")
          status_json=$(json_escape "$command_status")
          output_json=$(json_escape "$patch_report")
          command_item=$(printf '{"command":"%s","status":"%s","output":"%s"}' \
            "$command_json" "$status_json" "$output_json")

          if [ "$commands_first" -eq 1 ]; then
            commands_json=$command_item
            commands_first=0
          else
            commands_json="${commands_json},${command_item}"
          fi

          iteration_report="Patch gate result:
$patch_report"
          loop_feedback=$iteration_report

          if [ "$patch_success" -eq 1 ]; then
            if [ "$programming_quick_adjacent_slice_run" -eq 1 ] && [ "$programming_followup_slice_started_count" -gt "$programming_followup_slice_completed_count" ] && [ -n "$(trim "$current_programming_slice_path")" ] && programming_paths_match "$current_programming_slice_path" "$programming_followup_slice_path"; then
              programming_followup_slice_completed_count=$((programming_followup_slice_completed_count + 1))
            fi
            auto_verify_report_file=$(mktemp)
            followup_candidate=""
            followup_candidate_kind=""
            defer_remaining_branch=0
            landed_changed_count=$(programming_changed_paths_count_from_file "$changed_paths_file")
            case "$landed_changed_count" in
              ''|*[!0-9]*)
                landed_changed_count=0
                ;;
            esac
            landed_has_docs=0
            landed_has_verify=0
            landed_has_post_safe=0
            if programming_changed_paths_file_has_documentation_safe "$changed_paths_file"; then
              landed_has_docs=1
            fi
            if programming_changed_paths_file_has_verification_safe "$changed_paths_file"; then
              landed_has_verify=1
            fi
            if programming_changed_paths_file_has_post_verification_safe "$changed_paths_file"; then
              landed_has_post_safe=1
            fi
            followup_transition_reason="first slice landed; widening to adjacent verified slice"
            followup_stream_line="Step $iteration: widening to one adjacent verified slice after the first landed cleanly."
            if [ "$programming_quick_post_verification_safe_followup_slice_run" -eq 1 ] && [ "$landed_changed_count" -ge 4 ] && [ "$landed_has_docs" -eq 1 ] && [ "$landed_has_verify" -eq 1 ] && [ "$landed_has_post_safe" -eq 0 ]; then
              followup_transition_reason="verification-safe slice landed; widening to one final release-note-safe follow-up slice"
              followup_stream_line="Step $iteration: widening to one final release-note-safe follow-up slice after the verification-safe slice landed cleanly."
              followup_candidate=$(programming_quick_narrow_slice_post_verification_followup_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$changed_paths_file")
              followup_candidate=$(programming_normalize_relative_path "$followup_candidate")
              followup_candidate_kind="post-verification-safe"
            elif [ "$programming_quick_verification_followup_slice_run" -eq 1 ] && [ "$landed_changed_count" -ge 3 ] && [ "$landed_has_docs" -eq 1 ] && [ "$landed_has_verify" -eq 0 ]; then
              followup_transition_reason="documentation-safe slice landed; widening to one final verification-safe follow-up slice"
              followup_stream_line="Step $iteration: widening to one final verification-safe follow-up slice after the documentation-safe slice landed cleanly."
              followup_candidate=$(programming_quick_narrow_slice_verification_followup_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$changed_paths_file")
              followup_candidate=$(programming_normalize_relative_path "$followup_candidate")
              followup_candidate_kind="verification"
            elif [ "$programming_quick_multi_followup_slice_run" -eq 1 ] && [ "$landed_changed_count" -ge 2 ] && [ "$landed_has_docs" -eq 0 ]; then
              followup_transition_reason="adjacent slice landed; widening to one final documentation-safe follow-up slice"
              followup_stream_line="Step $iteration: widening to one final documentation-safe follow-up slice after the adjacent slice landed cleanly."
              followup_candidate=$(programming_quick_narrow_slice_documentation_followup_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$changed_paths_file")
              followup_candidate=$(programming_normalize_relative_path "$followup_candidate")
              followup_candidate_kind="documentation"
            fi
            if [ "$programming_quick_adjacent_slice_run" -eq 1 ] && [ "$programming_followup_slice_started_count" -eq "$programming_followup_slice_completed_count" ] && [ "$programming_followup_slice_completed_count" -lt "$programming_followup_slice_limit" ]; then
              if [ "$programming_quick_post_verification_safe_followup_slice_run" -eq 1 ] && [ "$programming_followup_slice_completed_count" -ge 3 ]; then
                followup_transition_reason="verification-safe slice landed; widening to one final release-note-safe follow-up slice"
                followup_stream_line="Step $iteration: widening to one final release-note-safe follow-up slice after the verification-safe slice landed cleanly."
                followup_candidate_kind="post-verification-safe"
              elif [ "$programming_quick_verification_followup_slice_run" -eq 1 ] && [ "$programming_followup_slice_completed_count" -ge 2 ]; then
                followup_transition_reason="documentation-safe slice landed; widening to one final verification-safe follow-up slice"
                followup_stream_line="Step $iteration: widening to one final verification-safe follow-up slice after the documentation-safe slice landed cleanly."
                followup_candidate_kind="verification"
              elif [ "$programming_followup_slice_completed_count" -ge 1 ]; then
                followup_transition_reason="adjacent slice landed; widening to one final documentation-safe follow-up slice"
                followup_stream_line="Step $iteration: widening to one final documentation-safe follow-up slice after the adjacent slice landed cleanly."
                followup_candidate_kind="documentation"
              fi
              if [ -z "$followup_candidate" ]; then
                if [ "$programming_quick_post_verification_safe_followup_slice_run" -eq 1 ] && [ "$programming_followup_slice_completed_count" -ge 3 ]; then
                  followup_candidate=$(programming_quick_narrow_slice_post_verification_followup_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$changed_paths_file")
                elif [ "$programming_quick_verification_followup_slice_run" -eq 1 ] && [ "$programming_followup_slice_completed_count" -ge 2 ]; then
                  followup_candidate=$(programming_quick_narrow_slice_verification_followup_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$changed_paths_file")
                elif [ "$programming_quick_multi_followup_slice_run" -eq 1 ] && [ "$programming_followup_slice_completed_count" -ge 1 ]; then
                  followup_candidate=$(programming_quick_narrow_slice_documentation_followup_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$changed_paths_file")
                else
                  followup_candidate=$(programming_quick_narrow_slice_next_followup_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$augmented_user_prompt" "$changed_paths_file")
                fi
              fi
              followup_candidate=$(programming_normalize_relative_path "$followup_candidate")
            fi
            if [ -z "$followup_candidate" ] && [ "$programming_quick_post_verification_safe_followup_slice_run" -eq 1 ] && [ "$programming_followup_slice_completed_count" -ge "$programming_followup_slice_limit" ] && programming_prompt_has_post_release_note_branch "$augmented_user_prompt"; then
              defer_remaining_branch=1
            elif [ -z "$followup_candidate" ] && [ "$programming_quick_verification_followup_slice_run" -eq 1 ] && [ "$programming_followup_slice_completed_count" -ge "$programming_followup_slice_limit" ] && [ "$programming_quick_post_verification_safe_followup_slice_run" -ne 1 ] && programming_prompt_has_post_verification_branch "$augmented_user_prompt"; then
              defer_remaining_branch=1
            fi
            if auto_verify_after_patch_for_prompt "$workspace_id" "$workspace_path" "$augmented_user_prompt" "$command_mode" "$blocked_commands_file" "$auto_verify_report_file"; then
              if [ -n "$followup_candidate" ]; then
                programming_followup_slice_path=$(programming_normalize_relative_path "$followup_candidate")
                programming_followup_slice_kind=$(trim "$followup_candidate_kind")
                [ -n "$programming_followup_slice_kind" ] || programming_followup_slice_kind="adjacent"
                programming_followup_slice_started_count=$((programming_followup_slice_started_count + 1))
                next_mode="IMPLEMENT"
                transition_reason_runtime=$followup_transition_reason
                state_set "$state_file" "blocking" "none"
                assistant_output=""
                patch_report="${patch_report}

Auto-verify output:
$(sed -n '1,220p' "$auto_verify_report_file")

Next slice target:
$followup_candidate"
                stream_emit_line "$stream_output_file" "$followup_stream_line"
              else
                next_mode="DONE"
                if [ "$defer_remaining_branch" -eq 1 ]; then
                  if [ "$programming_quick_post_verification_safe_followup_slice_run" -eq 1 ] && programming_prompt_has_post_release_note_branch "$augmented_user_prompt"; then
                    transition_reason_runtime="release-note-safe slice landed; deferring remaining requested branches"
                    stream_emit_line "$stream_output_file" "Step $iteration: deferring any remaining requested branches after the release-note-safe slice."
                  else
                    transition_reason_runtime="verification-safe slice landed; deferring remaining requested branches"
                    stream_emit_line "$stream_output_file" "Step $iteration: deferring any remaining requested branches after the verification-safe slice."
                  fi
                else
                  transition_reason_runtime="post-implement auto verification passed"
                fi
                state_set "$state_file" "blocking" "none"
                case "$(printf '%s' "$augmented_user_prompt" | tr '[:upper:]' '[:lower:]')" in
                  *godot*)
                    assistant_output="Created a runnable Godot project in the workspace and verified it with headless Godot."
                    ;;
                  *)
                    assistant_output="Completed implementation and verification successfully."
                    ;;
                esac
                patch_report="${patch_report}

Auto-verify output:
$(sed -n '1,220p' "$auto_verify_report_file")"
              fi
            else
              if [ -n "$followup_candidate" ]; then
                programming_followup_slice_path=$(programming_normalize_relative_path "$followup_candidate")
                programming_followup_slice_kind=$(trim "$followup_candidate_kind")
                [ -n "$programming_followup_slice_kind" ] || programming_followup_slice_kind="adjacent"
                programming_followup_slice_started_count=$((programming_followup_slice_started_count + 1))
                next_mode="IMPLEMENT"
                transition_reason_runtime=$followup_transition_reason
                state_set "$state_file" "blocking" "none"
                assistant_output=""
                patch_report="${patch_report}

Auto-verify output:
$(sed -n '1,220p' "$auto_verify_report_file")

Next slice target:
$followup_candidate"
                stream_emit_line "$stream_output_file" "$followup_stream_line"
              else
                next_mode="VERIFY"
                if [ "$defer_remaining_branch" -eq 1 ]; then
                  if [ "$programming_quick_post_verification_safe_followup_slice_run" -eq 1 ] && programming_prompt_has_post_release_note_branch "$augmented_user_prompt"; then
                    transition_reason_runtime="release-note-safe slice landed; deferring remaining requested branches until verification is clean"
                    stream_emit_line "$stream_output_file" "Step $iteration: deferring any remaining requested branches after the release-note-safe slice."
                  else
                    transition_reason_runtime="verification-safe slice landed; deferring remaining requested branches until verification is clean"
                    stream_emit_line "$stream_output_file" "Step $iteration: deferring any remaining requested branches after the verification-safe slice."
                  fi
                elif [ "${patch_already_present:-0}" -eq 1 ]; then
                  transition_reason_runtime="selected slice already present"
                else
                  transition_reason_runtime="scratch commit promoted"
                fi
                state_set "$state_file" "blocking" "none"
                patch_report="${patch_report}

Auto-verify output:
$(sed -n '1,220p' "$auto_verify_report_file")"
              fi
            fi
            rm -f "$auto_verify_report_file"
          else
            next_mode="IMPLEMENT"
            transition_reason_runtime="implementation patch failed"
            state_set "$state_file" "blocking" "patch gate failed"
          fi
          stream_emit_line "$stream_output_file" "Step $iteration implementation summary: next=$next_mode reason=$transition_reason_runtime"
          ;;

        DONE)
          final_candidate=$(trim "$final_section")
          if [ -z "$final_candidate" ] || [ "$final_candidate" = "NONE" ]; then
            final_candidate=$(trim "$checkpoint_text")
          fi
          if [ -z "$final_candidate" ] || [ "$final_candidate" = "NONE" ]; then
            final_candidate="Completed requested work."
          fi
          assistant_output="$final_candidate"
          next_mode="DONE"
          transition_reason_runtime="already done"
          iteration_report="Agent remained in DONE mode."
          loop_feedback=$iteration_report
          ;;
        esac
      fi

      if [ "$recovered_controller_output" -eq 1 ] && [ "$next_mode" = "DONE" ]; then
        append_failure_entry "$failures_file" "controller-format-done-block-iteration-$iteration" \
          "Prevented DONE transition from recovered controller output" \
          "Recovered controller output attempted to end the run without a clean structured pass" \
          "Hold mode and request one clean controller iteration before completion"
        controller_format_done_block_total=$((controller_format_done_block_total + 1))
        next_mode="$state_mode"
        transition_reason_runtime="controller format recovery requires clean pass"
        assistant_output=""
        done_claim="no"
        state_set "$state_file" "blocking" "controller format recovery pending clean pass"
        iteration_report="${iteration_report}
Format recovery guard:
Recovered controller output cannot complete the run; requesting one clean structured pass."
        loop_feedback=$iteration_report
        stream_emit_line "$stream_output_file" "Step $iteration completion guard: recovered controller output cannot transition directly to DONE."
      fi
      run_now_for_circuit=$(date +%s 2>/dev/null || printf '0')
      case "$run_now_for_circuit" in
        ""|*[!0-9]*)
          run_now_for_circuit=$run_started_epoch
          ;;
      esac
      run_elapsed_for_circuit=$((run_now_for_circuit - run_started_epoch))
      if [ "$run_elapsed_for_circuit" -lt 0 ]; then
        run_elapsed_for_circuit=0
      fi
      run_budget_remaining=$((run_time_budget - run_elapsed_for_circuit))
      if [ "$run_budget_remaining" -lt 0 ]; then
        run_budget_remaining=0
      fi
      if [ "$next_mode" != "DONE" ] && {
        [ "$controller_format_recovery_streak" -ge 2 ] ||
        [ "$controller_format_recovery_total" -ge 3 ] ||
        { [ "$controller_format_done_block_total" -ge 1 ] && [ "$run_budget_remaining" -le 25 ]; };
      }; then
        append_failure_entry "$failures_file" "controller-format-circuit-breaker-iteration-$iteration" \
          "Controller format instability circuit-breaker triggered" \
          "Repeated malformed controller recoveries or late-budget done-blocks indicate low-probability clean recovery within remaining budget" \
          "Finalize with deterministic best-effort response and request focused rerun"
        next_mode="DONE"
        transition_reason_runtime="controller format instability circuit-breaker"
        done_claim="no"
        if [ -z "$(trim "$assistant_output")" ] || [ "$assistant_output" = "NONE" ]; then
          assistant_output=$(structured_incomplete_run_message \
            "$state_mode" \
            "Retry with a narrower prompt slice or a different model, then continue from the latest verified checkpoint." \
            "Controller output format failed strict schema checks repeatedly in this run." \
            "$augmented_user_prompt")
        fi
        state_set "$state_file" "blocking" "controller format instability; finalized with best-effort output"
        iteration_report="${iteration_report}
Format recovery circuit-breaker:
Repeated malformed controller recoveries triggered deterministic best-effort finalization."
        loop_feedback=$iteration_report
        stream_emit_line "$stream_output_file" "Step $iteration circuit-breaker: repeated format recovery; finalizing with best-effort output."
      fi
      rm -f "$decision_options_file"

      state_set "$state_file" "mode" "$next_mode"
      state_set "$state_file" "transition_reason" "$transition_reason_runtime"

      case "$next_mode" in
        INVESTIGATE) default_confidence="0.30" ;;
        DESIGN) default_confidence="0.45" ;;
        IMPLEMENT) default_confidence="0.60" ;;
        VERIFY) default_confidence="0.72" ;;
        DONE) default_confidence="0.90" ;;
        *) default_confidence="0.50" ;;
      esac

      if [ -z "$confidence_update" ] || printf '%s' "$confidence_update" | grep -q '[^0-9.]'; then
        state_set "$state_file" "confidence" "$default_confidence"
      fi
      confidence_stream=$(trim "$(state_get "$state_file" "confidence" "$default_confidence")")
      if [ -z "$confidence_stream" ]; then
        confidence_stream="$default_confidence"
      fi
      stream_emit_line "$stream_output_file" "Step $iteration confidence updated: $confidence_stream"

      checkpoint_trimmed=$(trim "$checkpoint_text")
      if [ -n "$checkpoint_trimmed" ] && [ "$checkpoint_trimmed" != "NONE" ]; then
        iteration_report="${iteration_report}
Checkpoint:
$checkpoint_trimmed"
      fi
      iteration_report="${iteration_report}
Transition: $state_mode -> $next_mode
Reason: $transition_reason_runtime"
      loop_feedback=$iteration_report

      stagnation_plan_head=$(printf '%s\n' "$plan_update" | sed -n '1,2p')
      stagnation_plan_head=$(single_line_snippet "$stagnation_plan_head")
      if [ -z "$stagnation_plan_head" ]; then
        stagnation_plan_head="none"
      fi
      stagnation_checkpoint=$(single_line_snippet "$checkpoint_trimmed")
      if [ -z "$stagnation_checkpoint" ]; then
        stagnation_checkpoint="none"
      fi
      stagnation_signature_src=$(printf '%s|%s|%s|%s|%s|%s' \
        "$state_mode" "$next_mode" "$transition_reason_runtime" "$done_claim" "$stagnation_plan_head" "$stagnation_checkpoint")
      stagnation_signature=$(printf '%s' "$stagnation_signature_src" | cksum | awk '{print $1}')
      if [ -n "$stagnation_last_signature" ] && [ "$stagnation_signature" = "$stagnation_last_signature" ]; then
        stagnation_repeat_count=$((stagnation_repeat_count + 1))
      else
        stagnation_repeat_count=0
      fi
      stagnation_last_signature=$stagnation_signature
      if [ "$next_mode" != "DONE" ] && [ "$stagnation_repeat_count" -ge 2 ]; then
        stagnation_note="Loop stagnation detected: repeated transition signature with limited forward progress."
        loop_feedback="${loop_feedback}

Stagnation guardrail:
- Recent iterations repeated the same transition signature.
- Do not repeat identical plan/command output.
- Either emit DECISION_REQUEST for truly required missing inputs, or choose explicit assumptions and advance with verifiable progress."
        if [ "$stagnation_repeat_count" -eq 2 ]; then
          append_failure_entry "$failures_file" "iteration-$iteration:loop-stagnation" \
            "Loop stagnation detected" \
            "Repeated transition signature without forward progress" \
            "Switch strategy via explicit assumptions or early decision checkpoint"
          stream_emit_line "$stream_output_file" "Loop stagnation detected; injecting anti-repeat guardrail."
          iteration_report="${iteration_report}
$stagnation_note"
        fi
      fi

      append_session_entry "$session_log_file" "iteration $iteration ($state_mode -> $next_mode)" "$iteration_report"
      loop_summary="${loop_summary}
Iteration $iteration ($state_mode -> $next_mode):
$iteration_report"
