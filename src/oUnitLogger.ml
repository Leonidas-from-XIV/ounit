(*
   Logger for information and various OUnit events.
 *)

open OUnitTypes
open OUnitUtils

type logger = 
    {
      fwrite: log_event -> unit;
      fpos:   unit -> position option;
      fclose: unit -> unit;
    }

let results_style_1_X =
  OUnitConf.make
    "results_style_1_X"
    (fun r -> Arg.Set r)
    ~printer:string_of_bool
    false
    "Use OUnit 1.X results printer."

let string_of_event ev =
  let spf fmt = Printf.sprintf fmt in
  let string_of_result = 
    function
      | RSuccess -> "RSuccess"
      | RFailure (msg, _) -> spf "RFailure (%S, _)" msg
      | RError (msg, _)   -> spf "RError (%S, _)" msg
      | RSkip msg -> spf "RSkip %S" msg
      | RTodo msg -> spf "RTodo %S" msg
  in
  let string_of_log_severity =
    function
      | LError   -> "LError"
      | LWarning -> "LWarning"
      | LInfo    -> "LInfo"
  in
    match ev with 
      | GlobalEvent e ->
          begin
            match e with 
              | GConf str  -> spf "GConf %S" str
              | GStart     -> "GStart"
              | GEnd       -> "GEnd"
              | GResults _ -> "GResults"
          end
      | TestEvent (path,  e) ->
          begin
            match e with 
              | EStart ->
                  "EStart"
              | EEnd ->
                  "EEnd"
              | EResult result ->
                  spf "EResult (%s)" (string_of_result result)
              | ELog (lvl, str) ->
                  spf "ELog (%s, %S)" (string_of_log_severity lvl) str
              | ELogRaw str ->
                  spf "ELogRaw %S" str
          end

let format_event verbose log_event =
  match log_event.event with
    | GlobalEvent e ->
        begin
          match e with 
            | GConf str ->
                if verbose then
                  str^"\n"
                else
                  ""
            | GStart ->
                if verbose then
                  "Start testing.\n"
                else
                  ""
            | GEnd ->
                if verbose then
                  "End testing.\n"
                else
                  ""
            | GResults (running_time, results, test_case_count) -> 
                let separator1 = String.make (Format.get_margin ()) '=' in
                let separator2 = String.make (Format.get_margin ()) '-' in
                let buf = Buffer.create 1024 in
                let bprintf fmt = Printf.bprintf buf fmt in
                let print_results = 
                  List.iter 
                    (fun (path, test_result, pos_opt) -> 
                       if results_style_1_X () then
                         begin
                           bprintf "%s\n%s: %s\n\n%s\n%s\n" 
                             separator1 
                             (result_flavour test_result) 
                             (string_of_path path) 
                             (result_msg test_result) 
                             separator2
                         end
                       else
                         begin
                           bprintf "%s\n" separator1;
                           begin
                             match pos_opt with 
                               | Some pos ->
                                   bprintf "%s\n" (ocaml_position pos)
                               | None ->
                                   ()
                           end;
                           (* TODO: use backtrace *)
                           bprintf "Error: %s\n\n" 
                             (string_of_path path);
                           bprintf "%s\n" (result_msg test_result);
                           bprintf "%s\n" separator2;
                         end)
                in
                let filter f = 
                  let lst = 
                    List.filter 
                      (fun (_, test_result, _) -> f test_result)
                      results
                  in
                    lst, List.length lst
                in
                let errors, nerrors     = filter is_error in
                let failures, nfailures = filter is_failure in
                let skips, nskips       = filter is_skip in
                let todos, ntodos       = filter is_todo in

                  if not verbose then
                    bprintf "\n";

                  print_results errors;
                  print_results failures;
                  bprintf "Ran: %d tests in: %.2f seconds.\n" 
                    (List.length results) running_time;

                  (* Print final verdict *)
                  if was_successful results then 
                    begin
                      if skips = [] then
                        bprintf "OK"
                      else 
                        bprintf "OK: Cases: %d Skip: %d"
                          test_case_count nskips
                    end
                  else
                    begin
                      bprintf
                        "FAILED: Cases: %d Tried: %d Errors: %d \
                              Failures: %d Skip:%d Todo:%d" 
                        test_case_count 
                        (List.length results)
                        nerrors
                        nfailures
                        nskips
                        ntodos;
                    end;
                  bprintf "\n";
                  Buffer.contents buf
        end

    | TestEvent (path, e) ->
        begin
          let string_of_result = 
            if verbose then
              function
                | RSuccess        -> "ok\n"
                | RFailure (_, _) -> "FAIL\n"
                | RError (_, _)   -> "ERROR\n"
                | RSkip _         -> "SKIP\n"
                | RTodo _         -> "TODO\n"
            else
              function
                | RSuccess        -> "."
                | RFailure (_, _) -> "F"
                | RError (_, _)   -> "E"
                | RSkip _         -> "S"
                | RTodo _         -> "T"
          in
            if verbose then
              match e with 
                | EStart -> 
                    Printf.sprintf "%s start\n" (string_of_path path)
                | EEnd -> 
                    Printf.sprintf "%s end\n" (string_of_path path)
                | EResult result -> 
                    string_of_result result
                | ELog (lvl, str) ->
                    let prefix = 
                      match lvl with 
                        | LError -> "E"
                        | LWarning -> "W"
                        | LInfo -> "I"
                    in
                      prefix^": "^str
                | ELogRaw str ->
                    str
            else 
              match e with 
                | EStart _ | EEnd _ | ELog _ | ELogRaw _ -> ""
                | EResult result -> string_of_result result
        end

let file_logger fn =
  let chn = open_out fn in
  let line = ref 1 in
  let fwrite ev =
    let str =  format_event true ev in
    String.iter (function '\n' -> incr line | _ -> ()) str;
    output_string chn str;
    flush chn
  in
  let fpos () =
    Some { filename = fn; line = !line }
  in
  let fclose ()= 
    close_out chn
  in
    {
      fwrite = fwrite;
      fpos   = fpos;
      fclose = fclose;
    }


let std_logger verbose =
  let fwrite log_ev = 
    print_string (format_event verbose log_ev);
    flush stdout
  in
    {
      fwrite = fwrite;
      fpos   = (fun () -> None);
      fclose = ignore;
    }

let fun_logger fwrite fclose =
  {
    fwrite = (fun log_ev -> fwrite log_ev);
    fpos   = (fun () -> None);
    fclose = fclose;
  }

let null_logger =
  {
    fwrite = ignore;
    fpos   = (fun () -> None);
    fclose = ignore;
  }

let post_logger fpost = 
  let data = ref [] in
  let fwrite ev = data := ev :: !data in
  let fclose () = fpost (List.rev !data) in
    {
      fwrite = fwrite;
      fpos   = (fun () -> None);
      fclose = fclose;
    }

let report logger ev =
  logger.fwrite 
    {
      timestamp = now ();
      event = ev;
    }

let position logger =
  logger.fpos ()

let close logger =
  logger.fclose ()

let combine lst = 
  let rec fpos =
    function
      | logger :: tl ->
          begin
            match position logger with 
              | Some _ as pos ->
                  pos
              | None ->
                  fpos tl
          end
      | [] -> 
          None
  in
    {
      fwrite = 
        (fun log_ev -> 
           List.iter 
             (fun logger -> 
                logger.fwrite log_ev) lst);
      fpos   = (fun () -> fpos lst);
      fclose = 
        (fun () -> 
           List.iter (fun logger -> close logger) (List.rev lst));
    }

let create output_file_opt verbose logger =
  let std_logger= 
    std_logger verbose 
  in
  let file_logger = 
    match output_file_opt with 
      | Some fn ->
          file_logger fn
      | None ->
          null_logger
  in
    combine [std_logger; file_logger; logger]

module Test = 
struct 
  type t = 
      {
        driver: logger;
        test:   path;
      }

  let create driver path =
    {
      driver = driver;
      test   = path;
    }

  let raw_printf t fmt =
    Printf.ksprintf
      (fun s ->
         t.driver.fwrite 
           {
             timestamp = now ();
             event = TestEvent (t.test, (ELogRaw s))
           })
      fmt

  let logf t lvl fmt = 
    Printf.ksprintf
      (fun s ->
         t.driver.fwrite 
           {
             timestamp = now ();
             event = TestEvent (t.test, (ELog (lvl, s)))
           })
      fmt
end
