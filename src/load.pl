:- module(load, [ load_eng/0,
                  known_commands/1,
                  known_command_focus/2,
                  known_command_info/1,
                  known_command_info/2,
                  known_subcommands/2,
                  known_subcommand_info/2,
                  call_eng_cmd/4,
                  eng_cmd_help/2,
                  engfile_dir/1,
                  ingest_engfiles/1
                ]).

:- use_module(library(apply)).
:- use_module(library(filesex)).
:- use_module(library(readutil)).
:- use_module(englib).

% Note: Each time a new primary command (engineering focus) is added, add it to
% load_eng and known_commands.

load_eng.   % This used to have the use_module statements below as the body, but
            % this prevented them from being placed in the saved state for
            % distribution, so those are now top-level and this does nothing.
:- use_module('src/commands/dev').
:- use_module('src/commands/doc').
:- use_module('src/commands/help').
:- use_module('src/commands/run').
:- use_module('src/commands/system').
:- use_module('src/commands/exec_subcmds').
:- use_module('src/commands/versionctl').
:- use_module('src/datafmts/eqil').

known_commands([
                      "dev",
                      "doc",
                      "help",
                      "run",
                      "system",
                      "vctl" ]).

known_command_focus(Cmd, cmdfocus(Cmd, CmdFocus)) :-
    string_concat(Cmd, "_focus", CmdF),
    atom_string(CmdFPred, CmdF),
    ( current_predicate(CmdFPred, _), !, call(CmdFPred, CmdFocus)
    ; %% print_message(error, cmd_not_impl(Cmd)),
      CmdFocus = ""
    ).

known_command_info(Info) :-
    known_commands(Cmds),
    sort(Cmds, SortedCmds),
    maplist(known_command_focus, SortedCmds, CLS),
    maplist(show_cmd_focus(with_subcommands), CLS, ILS),
    append(ILS, ILSS),
    intercalate(ILSS, "\n", Info).

known_command_info(Info, main_only) :-
    known_commands(Cmds),
    sort(Cmds, SortedCmds),
    maplist(known_command_focus, SortedCmds, CLS),
    maplist(show_cmd_focus, CLS, ILS),
    intercalate(ILS, "\n", Info).

show_cmd_focus(cmdfocus(Cmd, CmdFocus), OutStr) :-
    format(atom(OutStr), '  ~w ~`-t ~w~72|', [ Cmd, CmdFocus ]).

show_cmd_focus(with_subcommands, cmdfocus(Cmd, CmdFocus), [OutCmd|OutSub]) :-
    format(atom(OutCmd), '  ~w ~`-t ~w~72|', [ Cmd, CmdFocus ]),
    %% format(atom(OutCmd), '  ~w~`-t~14+ ~w~72|', [ Cmd, CmdFocus ]),
    % n.b. format outputs an atom, not a string...
    known_subcommand_info(OutSub, Cmd).

known_subcommand_info(Info, Cmd) :-
    known_subcommands(Cmd, SubCmds),
    sort(SubCmds, SSubCmds),
    maplist(show_subcmd_focus(Cmd), SSubCmds, Info).

known_subcommands(Cmd, SubCmds) :-
    string_concat(Cmd, "_help", CmdH),
    atom_string(CmdHPred, CmdH),
    % Get the list of subcommands, and allow no failures either in the CmdHPred
    % or if there are no subcommands (the .eng file doesn't exist, is badly
    % formatted, or doesn't provide subcommands).
    (catch(setof(S, H^call(CmdHPred, S, H), SubCmds),
           _Err, % error(existence_error(procedure, CmdHPred/2), context(_,_))
           SubCmds = [])
    ; SubCmds = []
    ).

show_subcmd_focus(Cmd, SubCmd, OutStr) :-
    string_concat(Cmd, "_help", CmdH),
    atom_string(CmdHPred, CmdH),
    call(CmdHPred, SubCmd, H),
    (is_list(H), H = [CmdHelp|_]
    ; \+ is_list(H), CmdHelp = H
    ),
    format(atom(OutStr), '     ~w ~`.t~18+ ~w~72|', [ SubCmd, CmdHelp ]).

call_eng_cmd(_, Cmd, [], 1) :-
    % If Cmd was not given arguments and this is a command that expects a
    % sub-command, provide the user with help on the available sub-commands.
    known_subcommands(Cmd, Sub),
    \+ Sub == [], !,
    format('Please specify one of the ~w engineering sub-commands to perform:~n',
          [ Cmd ]),
    known_subcommand_info(Info, Cmd), !,
    intercalate(Info, "\n", OutStr),
    writeln(OutStr).

call_eng_cmd(Context, Cmd, CmdArgs, Sts) :-
    string_concat(Cmd, "_cmd", CmdOp),
    atom_string(CmdPred, CmdOp),
    ( current_predicate(CmdPred, _), !
    ; %% print_message(error, cmd_not_impl(Cmd)),
      fail),
    call(CmdPred, Context, CmdArgs, Sts).

eng_cmd_help(Cmd, HelpInfo) :-
    string_concat(Cmd, "_help", S),
    atom_string(CmdHelp, S),
    current_predicate(CmdHelp, _),
    call(CmdHelp, HelpInfo).

engfile_dir("_eng_").

find_engfile_dir(Dir, AbsDir) :-
    absolute_file_name(Dir, AbsDir),
    exists_directory(AbsDir), !.
find_engfile_dir(Dir, _) :-
    absolute_file_name(Dir, AbsDir),
    file_directory_name(AbsDir, Main),
    file_directory_name(Main, Main), !, fail.
find_engfile_dir(Dir, EngDir) :-
    absolute_file_name(Dir, AbsDir),
    file_directory_name(AbsDir, Main),
    file_directory_name(Main, Parent),
    file_base_name(AbsDir, EDir),
    directory_file_path(Parent, EDir, CheckNext),
    find_engfile_dir(CheckNext, EngDir).

ingest_engfiles(context(EngDir, TopDir)) :-
    engfile_dir(Dir),
    find_engfile_dir(Dir, EngDir),
    file_directory_name(EngDir, TopDir),
    directory_files(EngDir, Files),
    ingest_files(EngDir, Files), !,
    ingest_user_engfiles.
ingest_engfiles(context(EngDir, TopDir)) :-
    ingest_user_engfiles,
    engfile_dir(EngDir),
    file_directory_name(EngDir, TopDir),
    % exists_directory failed in the previous proposition.
    format('No eng files found (~w directory).~n', [ EngDir ]).

ingest_user_engfiles :-
    absolute_file_name("~/.config/eng", UserConfigDir,
                       [ access(read),
                         file_type(directory),
                         file_errors(fail),
                         expand(true) ]),
    exists_directory(UserConfigDir), !,
    directory_files(UserConfigDir, Files),
    ingest_files(UserConfigDir, Files).
ingest_user_engfiles.

ingest_files(Dir, Files) :-
    % Backtracks through each File: for that File, all the possible ingestion
    % methods are tried, and ultimately they all signal failure to cause
    % backtracking to the next file.
    member(File, Files),
    directory_file_path(Dir, File, FilePath),
    ingest_file(FilePath).
ingest_files(_, _).  %% When all backtracking above has been finished, return
                     %% success from here.

ingest_file(File) :- process_eng_file(File, true), !, fail.
ingest_file(_) :- fail.

process_eng_file(File, true) :-
    % Process files with an .eng extension that aren't hidden files (start with a
    % period).
    file_name_extension(_, ".eng", File),
    file_base_name(File, Name), \+ string_chars(Name, ['.'|_]),
    % Read the file, parse it, and assert the facts in the file for predicate use
    % elsewhere.
    read_file_to_string(File, Contents, []),
    print_message(informational, reading_eng_file(File)),
    parse_eng_eqil(File, Contents, Parsed),
    ( normalize_eqil(Parsed, Normalized), !,
      reprocess_eng_file(File, Normalized)
    ; (assert_eqil(Parsed), !
      ; print_message(error, eqil_nesting_too_deep(File))
      )
    ).

reprocess_eng_file(File, Updated_EQIL) :-
    !,
    emit_eqil(Updated_EQIL, OutText),
    string_concat(File, ".new", NewFile),
    open(NewFile, write, Out, [create([read, write]), type(text)]),
    format(Out, '~w~n', [OutText]),
    close(Out),
    rename_file(NewFile, File),
    print_message(informational, rewrote_eng_file(File)), !,
    parse_eng_eqil(File, OutText, Parsed),
    ( assert_eqil(Parsed), !
    ; print_message(error, eqil_nesting_too_deep(File))
    ).

prolog:message(reading_eng_file(File)) -->
    [ 'Ingesting ~w' - [File] ].
prolog:message(rewrote_eng_file(File)) -->
    [ 'Rewrote ~w' - [File] ].
prolog:message(eqil_nesting_too_deep(File)) -->
    [ 'Could not express ~w: maximum key nesting level depth exceeded ' - [File] ].
prolog:message(no_defined_subcmds(Cmd)) -->
    [ 'No currently user-defined "~w" sub-commands' - [ Cmd ] ].
prolog:message(invalid_subcmd(Cmd, SubCmd)) -->
    [ 'Invalid "~w" sub-command: ~w~n' - [ Cmd, SubCmd ] ],
    { known_subcommands(Cmd, CS) },
    [ 'Valid sub-commands: ~w~n' - [ CS ] ].
