:- module(system_eng, [ system_cmd/3, system_focus/1,
                        system_help/1, system_help/2 ]).
% n.b. the module name cannot be "system" because that is reserved in SWI Prolog.

:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(strings)).
:- use_module('../englib').
:- use_module(exec_subcmds).
:- use_module('../load').
:- use_module('../datafmts/lando').
:- use_module('../lando_tool').
:- use_module('../lando_validate').
:- use_module('../fret_kind2').

:- dynamic system_spec/1.


system_focus("Systems Engineering").

system_help(Info) :-
    engfile_dir(EngDirV),
    [EngDir] = [ EngDirV ],
    Info = {|string(EngDir)||
| Perform a SYSTEMS engineering task.
|
| Systems engineering involves the specification of the components and
| their relationships with this system.  It also associates those components
| with the system requirements.  System requirements can be validated for
| consistency, completeness, and lack of conflicts, and outputs from the
| system specification can be generated.
|
| System-level information is specified in one or more .eng files in EQIL
| format in the {EngDir} directory of the project.
|
|   system =
|     spec =
|       SPECIFICATION =
|         name = NAME OF SPECIFICATION
|         file = TOP_LEVEL_RELATIVE_FILENAME(S)
|         format = { lando | other }
|         generate =
|           OUTPUT_FILENAME
|             format = { ALL | fret | json | markdown | fret_kind2 }
|
|     model =
|       kind2 =
|         KIND2_NODE_NAME =
|           output = OUTPUT_VAR(S)
|           inputs = INPUT_VARS
|           file = KIND2_NODE_FILENAME
|}.

system_help(list, "List project's system specifications").
system_help(validate, "Check validity of system specifications").
system_help(gen, "Generate system specification outputs (e.g. lando to JSON)").

system_known_specification_types([ "lando" ]).

system_cmd(_, ['list'|_], 0) :-
    writeln('Known system specifications:'), show_system_specs(_); true.

system_cmd(_, ['validate'], specify_ssl_id) :- !.
system_cmd(Context, ['validate', 'ALL'], Result) :-
    process_system_specs(Context, validate_system_spec, Result), !.
system_cmd(Context, ['validate'|Specs], Result) :-
    process_system_specs(Context, validate_system_spec, Specs, Result), !.

system_cmd(_, ['gen'], specify_ssl_id) :- !.
system_cmd(Context, ['gen', 'ALL'], Result) :-
    process_system_specs(Context, generate_system_spec, Result), !.
system_cmd(Context, ['gen'|Specs], Result) :-
    process_system_specs(Context, generate_system_spec, Specs, Result), !.

system_cmd(_, [Cmd|_], invalid_subcmd(system, Cmd)).

% ----------------------------------------------------------------------

process_system_specs(Context, Op, Result) :-
    Context = context(_, TopDir),
    working_directory(_, TopDir),
    (setof(S, eng:key(system, spec, S), Specs); Specs = []),
    maplist(call(Op, Context), Specs, Result).

process_system_specs(Context, Op, Specs, Result) :-
    Context = context(_, TopDir),
    working_directory(_, TopDir),
    findall(R, (member(Spec, Specs), call(Op, Context, Spec, R)), Result).

prolog:message(specify_ssl_id) -->
    [ 'Please specify the system specification to process (or "ALL")~n' - [] ].
prolog:message(invalid_system_spec(Spec)) -->
    [ 'Validation failed for system specification "~w"~n' - [ Spec ] ].
prolog:message(unknown_spec_format(Spec, Format)) -->
    [ 'Unknown system specification format (~w) for spec "~w"~n' - [ Format,
                                                                     Spec ] ].
prolog:message(spec_format_not_specified(Spec)) -->
    [ 'No format specified for system specification "~w"~n' - [ Spec ] ].
prolog:message(no_spec_file(Spec)) -->
    [ 'No file provided for system specification "~w".~n' - [ Spec ] ].
prolog:message(unknown_spec(Spec)) -->
    [ 'Unknown system specification "~w"; see "eng system list".~n' - [ Spec ] ].

find_spec(Input, Input) :- eng:key(system, spec, Input), !.
find_spec(Input, Spec) :- atom_string(Input, InpStr),
                          eng:eng(system, spec, Spec, name, InpStr), !.

with_spec_format_and_file(InputSpec, Op, R) :-
    find_spec(InputSpec, Spec), !,
    with_spec_format_and_file_(Spec, Op, R).
with_spec_format_and_file(Spec, _, unknown_spec(Spec)).

with_spec_format_and_file_(Spec, Op, R) :-
    eng:eng(system, spec, Spec, format, Format), !,
    with_spec_format_and_file_(Spec, Op, Format, R).
with_spec_format_and_file_(Spec, _, 1) :-
    print_message(error, spec_format_not_specified(Spec)).

with_spec_format_and_file_(Spec, Op, Format, R) :-
    system_known_specification_types(Known),
    member(Format, Known), !,
    with_spec_format_and_file_(Spec, Op, Format, known, R).
with_spec_format_and_file_(Spec, _, Format, unknown_spec_format(Spec, Format)).

with_spec_format_and_file_(Spec, Op, Format, known, R) :-
    eng:eng(system, spec, Spec, file, SpecFile), !,
    ( call(Op, Spec, Format, SpecFile, R), !
    ; print_message(error, invalid_system_spec(Spec)), R = 1
    ).
with_spec_format_and_file_(Spec, _, _, _, 1) :-
    print_message(error, no_spec_file(Spec)).

% ----------------------------------------------------------------------

show_system_specs(Spec) :-
    eng:key(system, spec, Spec),
    show_system_spec(Spec).

show_system_spec(Spec) :-
    eng:eng(system, spec, Spec, name, Name),
    show_system_spec(Spec, Name).
show_system_spec(Spec) :-
    \+ eng:key(system, spec, Spec, name),
    show_system_spec(Spec, "").

show_system_spec(Spec, Name) :-
    eng:eng(system, spec, Spec, format, Format),
    show_system_spec(Spec, Name, Format).
show_system_spec(Spec, Name) :-
    \+ eng:key(system, spec, Spec, format),
    show_system_spec(Spec, Name, "?fmt?").

show_system_spec(Spec, Name, Format) :-
    format('  [~w] ~w: ~w~n', [ Format, Name, Spec ]),
    fail. % backtrack and try the next one

% ----------------------------------------------------------------------

validate_system_spec(Context, InputSpec, R) :-
    with_spec_format_and_file(InputSpec, validate_spec(Context), R).

validate_spec(Context, Spec, "lando", SpecFile, R) :-
    parse_lando_file(SpecFile, SSL), !,
    validate_lando(SSL, Problems),
      length(Problems, NumProbs),
    ( Problems == []
    -> validate_lando_fret(Context, Spec, SSL, R), !
    ; maplist(show_lando_validation_error(Spec, SpecFile), Problems),
      print_message(error, lando_validation_errors(Spec, SpecFile, NumProbs)),
      R = NumProbs
    ).
validate_spec(_, Spec, Format, SpecFile, 1) :-
    print_message(error, invalid_parse(Format, Spec, SpecFile)).
validate_spec(_, _, _, _, 1).

validate_lando_fret(Context, Spec, SSL, R) :-
    ( eng:eng(system, spec, Spec, generate, Dir, format, "fret_kind2")
    ; Dir = "fret_kind2"
    ),
    ensure_dir(Dir),
    !,
    % if no FRET, the next should not succeed and this predicate is false
    write_lando_fret_kind2(Dir, SSL, OutFiles),
    maplist(validate_lando_fret_cc(Context), OutFiles, Results),
    process_kind2_results(Results, R).

prolog:message(kind2_good(NPass)) -->
    ["TOTAL: PASS  (~w checks)~n" - [ NPass ] ].
prolog:message(kind2_good_with_exp_failures(NPass, NExpFailures)) -->
    { NTot is NPass + NExpFailures },
    ["TOTAL: PASS  (~w checks | ~w passed, ~w FAILED AS EXPECTED)~n"
     - [ NTot, NPass, NExpFailures ]].
prolog:message(kind2_good_with_unexp_good(NPass, NUnexpPass)) -->
    { NTot is NPass + NUnexpPass },
    ["TOTAL: PASS  (~w checks | ~w passed (~w of those UNEXPECTEDLY))~n"
     - [ NTot, NTot, NUnexpPass ]].
prolog:message(kind2_good_with_unexpected(NPass, NExpFail, NUnexpPass)) -->
    { NTot is NPass + NExpFail + NUnexpPass,
      NGood is NPass + NUnexpPass
    },
    ["TOTAL: PASS  (~w checks | ~w passed (~w of those UNEXPECTEDLY), ~w FAILED AS EXPECTED)~n"
     - [ NTot, NGood, NUnexpPass, NExpFail ]].
prolog:message(kind2_failures(0, NPass, NFail, 0, 0)) -->
    { NTot is NPass + NFail }, !,
    ["TOTAL: ~w FAILED  (~w checks | ~w passed)~n"
     - [NFail, NTot, NPass] ].
prolog:message(kind2_failures(NInv, NPass, NFail, 0, 0)) -->
    { NTot is NInv + NPass + NFail },
    ["TOTAL: ~w+~w FAILED  (~w checks | ~w passed)~n"
     - [NFail, NInv, NTot, NPass] ].
prolog:message(kind2_failures(0, NPass, NFail, 0, NUnexpPass)) -->
    { NTot is NPass + NFail + NUnexpPass,
      NGood is NPass + NUnexpPass
    }, !,
    ["TOTAL: ~w FAILED  (~w checks | ~w passed (~w of those UNEXPECTEDLY)~n"
     - [NFail, NTot, NGood, NUnexpPass] ].
prolog:message(kind2_failures(NInv, NPass, NFail, 0, NUnexpPass)) -->
    { NTot is NInv + NPass + NFail + NUnexpPass,
      NGood is NPass + NUnexpPass
    },
    ["TOTAL: ~w+~w FAILED  (~w checks | ~w passed (~w of those UNEXPECTEDLY)~n"
     - [NFail, NInv, NTot, NGood, NUnexpPass] ].
prolog:message(kind2_failures(0, NPass, NFail, NExpFail, 0)) -->
    { NTot is NPass + NFail + NExpFail }, !,
    ["TOTAL: ~w FAILED  (~w checks | ~w passed, ~w FAILED AS EXPECTED)~n"
     - [NFail, NTot, NPass, NExpFail] ].
prolog:message(kind2_failures(NInv, NPass, NFail, NExpFail, 0)) -->
    { NTot is NInv + NPass + NFail + NExpFail },
    ["TOTAL: ~w+~w FAILED  (~w checks | ~w passed, ~w FAILED AS EXPECTED)~n"
     - [NFail, NInv, NTot, NPass, NExpFail] ].
prolog:message(kind2_failures(0, NPass, NFail, NExpFail, NUnexpPass)) -->
    { NTot is NPass + NFail + NExpFail + NUnexpPass,
      NGood is NPass + NUnexpPass
    }, !,
    ["TOTAL: ~w FAILED  (~w checks | ~w passed (~w of those UNEXPECTEDLY), ~w FAILED AS EXPECTED)~n"
     - [NFail, NTot, NGood, NUnexpPass, NExpFail] ].
prolog:message(kind2_failures(NInv, NPass, NFail, NExpFail, NUnexpPass)) -->
    { NTot is NInv + NPass + NFail + NExpFail + NUnexpPass,
      NGood is NPass + NUnexpPass
    },
    ["TOTAL: ~w+~w FAILED  (~w checks | ~w passed (~w of those UNEXPECTEDLY), ~w FAILED AS EXPECTED)~n"
     - [NFail, NInv, NTot, NGood, NUnexpPass, NExpFail] ].

process_kind2_results(Results, R) :-
    append(Results, All),
    process_kind2_results(All, _{ninv:0,
                                 npass:0,
                                 nfail:0,
                                 nfailAsExp:0,
                                 nUnexpPass:0}, R).

process_kind2_results([], Stats, 0) :-
    get_dict(ninv, Stats, 0),
    get_dict(nfail, Stats, 0),
    get_dict(nfailAsExp, Stats, 0),
    get_dict(nUnexpPass, Stats, 0),
    !,
    get_dict(npass, Stats, NPass),
    print_message(success, kind2_good(NPass)).
process_kind2_results([], Stats, 0) :-
    get_dict(ninv, Stats, 0),
    get_dict(nfail, Stats, 0),
    get_dict(nUnexpPass, Stats, 0),
    !,
    get_dict(npass, Stats, NPass),
    get_dict(nfailAsExp, Stats, NFailAsExp),
    print_message(warning, kind2_good_with_exp_failures(NPass, NFailAsExp)).
process_kind2_results([], Stats, 0) :-
    get_dict(ninv, Stats, 0),
    get_dict(nfail, Stats, 0),
    get_dict(nfailAsExp, Stats, 0),
    !,
    get_dict(npass, Stats, NPass),
    get_dict(nUnexpPass, Stats, NUnexpPass),
    print_message(warning, kind2_good_with_unexp_good(NPass, NUnexpPass)).
process_kind2_results([], Stats, 0) :-
    get_dict(ninv, Stats, 0),
    get_dict(nfail, Stats, 0),
    !,
    get_dict(npass, Stats, NPass),
    get_dict(nfailAsExp, Stats, NFailAsExp),
    get_dict(nUnexpPass, Stats, NUnexpPass),
    print_message(warning, kind2_good_with_unexpected(NPass, NFailAsExp,
                                                      NUnexpPass)).
process_kind2_results([], Stats, 0) :-
    !,
    get_dict(nfail, Stats, NFail),
    get_dict(ninv, Stats, NInv),
    get_dict(npass, Stats, NPass),
    get_dict(nfailAsExp, Stats, NFailAsExp),
    get_dict(nUnexpPass, Stats, NUnexpPass),
    print_message(error, kind2_failures(NInv, NPass, NFail, NFailAsExp,
                                        NUnexpPass)).

process_kind2_results([ignored|KS], Stats, R) :-
    !,
    process_kind2_results(KS, Stats, R).
process_kind2_results([invalid|KS], Stats, R) :-
    !,
    get_dict(ninv, Stats, NInv),
    succ(NInv, U),
    put_dict(ninv, Stats, U, UpdStats),
    process_kind2_results(KS, UpdStats, SR),
    succ(SR, R).
process_kind2_results([passed|KS], Stats, R) :-
    !,
    get_dict(npass, Stats, NPass),
    succ(NPass, U),
    put_dict(npass, Stats, U, UpdStats),
    process_kind2_results(KS, UpdStats, R).
process_kind2_results([failed|KS], Stats, R) :-
    !,
    get_dict(nfail, Stats, NFail),
    succ(NFail, U),
    put_dict(nfail, Stats, U, UpdStats),
    process_kind2_results(KS, UpdStats, SR),
    succ(SR, R).
process_kind2_results([failed_as_expected|KS], Stats, R) :-
    !,
    get_dict(nfailAsExp, Stats, NFailAsExp),
    succ(NFailAsExp, U),
    put_dict(nfailAsExp, Stats, U, UpdStats),
    process_kind2_results(KS, UpdStats, R).
process_kind2_results([unexpectedly_passed|KS], Stats, R) :-
    !,
    get_dict(nUnexpPass, Stats, NUnexpPass),
    succ(NUnexpPass, U),
    put_dict(nUnexpPass, Stats, U, UpdStats),
    process_kind2_results(KS, UpdStats, SR),
    succ(SR, R).
process_kind2_results([satisfiable|KS], Stats, R) :-
    !,
    get_dict(npass, Stats, NPass),
    succ(NPass, U),
    put_dict(npass, Stats, U, UpdStats),
    process_kind2_results(KS, UpdStats, R).
process_kind2_results(O,S,99) :-
    format('ERR: unhandled kind2 results: ~w~n  stats = ~w~n~n', [O, S]),
    fail.


validate_lando_fret_cc(Context, contract(OutFile), Status) :-
    validate_lando_fret_cc(Context, contract, OutFile, Status).
validate_lando_fret_cc(Context, model(OutFile), Status) :-
    validate_lando_fret_cc(Context, model, OutFile, Status).
validate_lando_fret_cc(Context, Kind2Mode, OutFile, Status) :-
    directory_file_path(OutD, _, OutFile),
    %absolute_file_name(OutFile, OutFilePath),
    file_name_extension(OutBase, 'lus', OutFile),
    string_concat(OutBase, "_result", ResultBase),
    file_name_extension(ResultBase, 'json', ResultFile),
    kind2_validate(Context, OutFile, OutD, Kind2Mode, ResultFile, Status).

show_lando_validation_error(Spec, SpecFile, Err) :-
    print_message(error, lando_validation_error(Spec, SpecFile, Err)).

prolog:message(invalid_parse(Format, Spec, SpecFile)) -->
    [ 'Validation Error: unable to parse ~w format~n  [~w = ~w]~n' -
      [ Format, SpecFile, Spec ] ].
prolog:message(lando_validation_error(Spec, SpecFile, Err)) -->
    [ 'Validation Error: ~w~n  [~w = ~w]~n' - [ Err, SpecFile, Spec ] ].
prolog :message(number_lando_validation_errors(Spec, SpecFile, Count)) -->
    [ 'Total of ~w validation Errors~n  [~w = ~w]~n' -
      [ Count, SpecFile, Spec ] ].


% ----------------------------------------------------------------------

generate_system_spec(_, InputSpec, R) :-
    with_spec_format_and_file(InputSpec, generate_spec, R).

generate_spec(Spec, "lando", SpecFile, Result) :-
    parse_lando_file(SpecFile, SSL), !,
    findall(R, generate_spec_outputs(Spec, "lando", SSL, R), Results),
    sum_list(Results, Result).
generate_spec(_, _, _, 1).

generate_spec_outputs(Spec, "lando", SSL, Result) :-
    eng:key(system, spec, Spec, generate, OutFile),
    eng:eng(system, spec, Spec, generate, OutFile, format, "json"),
    ensure_file_loc(OutFile),
    open(OutFile, write, OutStrm),
    ( write_lando_json(OutStrm, SSL)
    -> Result = 0,
       print_message(information, wrote_lando_as("JSON", Spec, OutFile))
    ; Result = 1,
      print_message(error, did_not_write(Spec, OutFile, "json"))
    ).
generate_spec_outputs(Spec, "lando", SSL, Result) :-
    eng:key(system, spec, Spec, generate, OutFile),
    eng:eng(system, spec, Spec, generate, OutFile, format, "markdown"),
    ensure_file_loc(OutFile),
    open(OutFile, write, OutStrm),
    (write_lando_markdown(OutStrm, SSL)
    -> Result = 0,
       print_message(information, wrote_lando_as("Markdown", Spec, OutFile))
    ; Result = 1,
      print_message(error, did_not_write(Spec, OutFile, "markdown"))
    ).
generate_spec_outputs(Spec, "lando", SSL, Result) :-
    eng:key(system, spec, Spec, generate, OutFile),
    eng:eng(system, spec, Spec, generate, OutFile, format, "fret"),
    ensure_file_loc(OutFile),
    open(OutFile, write, OutStrm),
    (write_lando_fret(OutStrm, SSL)
    -> Result = 0,
       print_message(information, wrote_lando_as("FRET", Spec, OutFile))
    ; Result = 1,
      print_message(error, did_not_write(Spec, OutFile, "fret"))
    ).
generate_spec_outputs(Spec, "lando", SSL, Result) :-
    eng:key(system, spec, Spec, generate, OutDir),
    eng:eng(system, spec, Spec, generate, OutDir, format, "fret_kind2"),
    (write_lando_fret_kind2(OutDir, SSL, OutFiles)
    -> Result = 0,
       wrote_file_messages(Spec, "fret_kind2", OutFiles)
    ; Result = 1,
      print_message(error, did_not_write(Spec, OutDir, "fret_kind2"))
    ).
generate_spec_outputs(Spec, "lando", SSL, Result) :-
    eng:key(system, spec, Spec, generate, OutFile),
    eng:eng(system, spec, Spec, generate, OutFile, format, "RACK"),
    ensure_file_loc(OutFile),
    open(OutFile, write, OutStrm),
    (write_lando_rack(OutStrm, SSL)
    -> Result = 0,
       print_message(information, wrote_lando_as("FRET RACK", Spec, OutFile))
    ; Result = 1,
      print_message(error, did_not_write(Spec, OutFile, "FRET RACK"))
    ).

wrote_file_messages(_, _, []).
wrote_file_messages(Spec, Kind, [contract(OutFile)|FS]) :-
    string_concat(Kind, " contract", FKind),
    print_message(information, wrote_lando_as(FKind, Spec, OutFile)),
    wrote_file_messages(Spec, Kind, FS).
wrote_file_messages(Spec, Kind, [model(OutFile)|FS]) :-
    string_concat(Kind, " model", FKind),
    print_message(information, wrote_lando_as(FKind, Spec, OutFile)),
    wrote_file_messages(Spec, Kind, FS).

prolog:message(wrote_file(Spec, OutFile, Kind)) -->
    [ 'Wrote lando spec "~w" to ~w file ~w~n' - [ Spec, Kind, OutFile ]].
prolog:message(did_not_write(_Spec, OutFile, Kind)) -->
    [ 'Unable to write ~w to file ~w due to errors~n' - [ Kind, OutFile ]].
