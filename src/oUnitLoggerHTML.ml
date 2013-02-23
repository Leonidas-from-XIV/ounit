(*
   HTML logger for OUnit.
 *)

open OUnitTypes
open OUnitLogger
open OUnitUtils
open OUnitResultSummary

let global_output_html_dir = 
  let value =
    OUnitConf.make
      "output_html_dir"
      (fun r -> Arg.Set_string r)
      ~printer:(Printf.sprintf "%S")
      ""
      "Output directory of the HTML files."
  in
    fun () ->
      match value () with 
        | "" -> None
        | fn -> Some fn

let render dn events = 
  let smr =
    OUnitResultSummary.of_log_events events 
  in
  let () =
    if not (Sys.file_exists dn) then
      Unix.handle_unix_error (fun () -> Unix.mkdir dn 0o755) ()
  in

  let chn = open_out (Filename.concat dn "oUnit.css") in
  let () = 
    output_string chn OUnitLoggerHTMLData.oUnit_css;
    close_out chn
  in

  let chn = open_out (Filename.concat dn "oUnit.js") in
  let () = 
    output_string chn OUnitLoggerHTMLData.oUnit_js;
    close_out chn
  in

  let chn = open_out (Filename.concat dn "index.html") in
  let printf fmt = Printf.fprintf chn fmt in
  printf "\
<html>
  <head>
    <title>Test suite %s</title>
    <meta http-equiv='Content-Type' content='text/html;charset=%s'/>
    <link href='oUnit.css' rel='stylesheet' type='text/css'/>
    <script language='javascript' src='oUnit.js'></script>
  </head>
  <body onload=\"displaySuccess('none');\">
    <div id='navigation'>
        <button id='toggleVisibiltySuccess' onclick='toggleSuccess();'>Show success</button>
        <button id='nextTest' onclick='nextTest();'>Next test</button>
        <button id='gotoTop' onclick='gotoTop();'>Goto top</button>
    </div>
    <h1>Test suite %s</h1>
    <div class='ounit-results'>
      <h2>Results</h2>
      <div class='ounit-results-content'>\n"
  smr.suite_name smr.charset smr.suite_name; 
  begin
    let printf_result clss label num =
      printf 
        "<div class='ounit-results-%s'>\
           %s: <span class='number'>%d</span>\
         </div>"
        clss label num
    in
    let printf_non0_result clss label num =
      if num > 0 then
        printf_result clss label num
    in
      printf
        "<div id='ounit-results-started-at'>\
           Started at: %s
         </div>" (date_iso8601 smr.start_at);
      printf 
        "<div class='ounit-results-duration'>\
           Total duration: <span class='number'>%.3fs</span>\
         </div>" smr.running_time;
      printf_result "test-count" "Tests count" smr.test_case_count;
      printf_non0_result "errors" "Errors" smr.errors;
      printf_non0_result "failures" "Failures" smr.failures;
      printf_non0_result "skips" "Skipped" smr.skips;
      printf_non0_result "todos" "TODO" smr.todos;
      printf_result "successes" "Successes" smr.successes;

      (* Print final verdict *)
      if was_successful smr.global_results then 
        printf "<div class='ounit-results-verdict'>Success</div>"
      else
        printf "<div class='ounit-results-verdict ounit-failure'>Failure</div>"
  end;

  printf "\
      </div>
    </div>
    <div class='ounit-conf'>
      <h2>Configuration</h2>
      <div class='ounit-conf-content'>\n";
  List.iter (printf "%s<br/>\n") smr.conf;
  printf ("\
      </div>
    </div>
");
  List.iter
    (fun test_data ->
       let class_result, text_result = 
         match test_data.test_result with 
           | RSuccess        -> "ounit-success", "succeed"
           | RFailure (_, _) -> "ounit-failure", "failed"
           | RError (_, _)   -> "ounit-error", "error"
           | RSkip _         -> "ounit-skip", "skipped"
           | RTodo _         -> "ounit-todo", "TODO"
       in
       let class_severity_opt = 
         function
           | Some LError   -> "ounit-log-error"
           | Some LWarning -> "ounit-log-warning"
           | Some LInfo    -> "ounit-log-info"
           | None -> ""
       in
       printf "
    <div class='ounit-test %s'>
      <h2>%s (%s)</h2>
      <div class='ounit-started-at'>Started at: %s</div>
      <div class='ounit-duration'>Test duration: %0.3fs</div>
      <div class='ounit-log'>\n" 
         class_result
         test_data.test_name 
         text_result
         (date_iso8601 test_data.timestamp_start)
         (test_data.timestamp_end -. test_data.timestamp_start);
       printf "<span class='ounit-timestamp'>%0.3fs</span>Start<br/>\n" 
         0.0;
       List.iter (fun (tmstp, svrt, str) ->
                    printf "\
        <span class='%s'><span class='ounit-timestamp'>%0.3fs</span>%s</span><br/>\n" 
                      (class_severity_opt svrt) tmstp str)
         test_data.log_entries;
       printf "<span class='ounit-timestamp'>%0.3fs</span>End<br/>\n" 
         (test_data.timestamp_end -. test_data.timestamp_start);
       printf "<div class='ounit-result'>";
       begin
         (* TODO: use backtrace *)
         match test_data.test_result with 
           | RSuccess -> printf "Success."
           | RFailure (str, backtrace) -> printf "Failure:<br/>%s" str
           | RError (str, backtrace) -> printf "Error:<br/>%s" str
           | RSkip str -> printf "Skipped:<br/>%s" str
           | RTodo str -> printf "Todo:<br/>%s" str
       end;
       printf "</div>";
       printf "\
      </div>
    </div>\n"; (* TODO: results, end timestamp *))
    smr.tests;
  printf "\
  </body>
</html>";
  close_out chn

let create () =
  match global_output_html_dir () with 
    | Some dn ->
        post_logger (render dn)
    | None ->
        null_logger
