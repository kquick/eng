:- module(fret_kind2, [ fret_kind2/3,
                        normalize_kind2_var/2
                      ]).

:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(strings)).
:- use_module('src/datafmts/lando').
:- use_module('englib').
:- use_module(lando_fret).


%% ----------------------------------------------------------------------

fret_kind2(FretReqs, FretMents, Kind2Comps) :-
    get_dict(requirements, FretMents, Reqs),
    get_dict(variables, FretMents, Vars),
    !,
    connected_components(Reqs, FretReqs, 0, CComps),
    fret_to_kind2(Vars, CComps, Kind2Comps).

fret_to_kind2(_, [], []).
fret_to_kind2(Vars, [comp(N, CompName, Reqs, CVars)|CCs], [K2|K2s]) :-
    fret_to_kind2(Vars, CCs, K2s),
    reqs_to_kind2(Vars, CompName, Reqs, CVars, Kind2),
    K2 = _{ compNum: N,
            compName: CompName,
            kind2: Kind2
          }.

%% ----------------------------------------------------------------------

%% Group input requirements into "connected components".  The kind2 analysis is
%% done with past-time LTL, so requirements are connected if they share variable
%% references in the responses.  This will return a list of the CC's (Connected
%% Components) that can be created from the provided requirements.

connected_components([], _, _, []).
connected_components([R|Reqs], FRInfo, N, [CC|CComps]) :-
    req_info(FRInfo, R, RInfo),
    req_resp_vars(RInfo, Vars),
    ccomp(FRInfo, N, R, Vars, Reqs, CC, RemReqs),
    succ(N, M),
    connected_components(RemReqs, FRInfo, M, CComps).

ccomp(_, N, Req, RespVars, [], comp(N, CName, [Req], RespVars), []) :-
    % n.b. the collected RespVars are returned as the set of applicable output
    % vars for this CC.  This could be reconstructed by getting the set of all
    % vars from the Reqs in the CC and filtering by idType="Output", but since
    % they've already been collected here...
    get_dict(semantics, Req, ReqSemantics),
    get_dict(component_name, ReqSemantics, CName).
ccomp(FRInfo, N, Req, RespVars, [R|RS], comp(N, Name, [R|CReqs], CVars), RemReqs) :-
    get_dict(semantics, Req, ReqSemantics),
    get_dict(semantics, R, RSemantics),
    get_dict(component_name, ReqSemantics, CName),
    get_dict(component_name, RSemantics, CName),
    req_info(FRInfo, R, RInfo),
    req_resp_vars(RInfo, Vars),
    member(V, Vars),
    member(V, RespVars),
    % same component name, and overlap between R and Req response vars: R is in
    % this component
    !,
    append(Vars, RespVars, TTLVars), % KWQ: nub?
    ccomp(FRInfo, N, Req, TTLVars, RS, comp(N, Name, CReqs, CVars), RemReqs).
ccomp(FRInfo, N, Req, RespVars, [R|RS], CC, [R|RemReqs]) :-
    ccomp(FRInfo, N, Req, RespVars, RS, CC, RemReqs).

req_info([RI|_], R, RI) :-
    get_dict(requirement, RI, RIR),
    get_dict(reqid, R, RID),
    get_dict(reqid, RIR, RID).
req_info([_|RIS], R, RI) :-
    req_info(RIS, R, RI).

req_resp_vars(RI, RespVars) :-
    get_dict(fretment, RI, fretment(_, _, _, _, response_info(_, RespVars))).

%% ----------------------------------------------------------------------

% All Internal and Mode variables should always be defined.  They may not be used
% by the requirements in this CC, but they shouldn't hurt anything by being
% defined.

%% implicit_vars(Vars, Kind2Decls) :-
%%     implicit_vars_(Vars, Decls),
%%     intercalate(Vars, "\n", Decls).

implicit_vars([], []).
implicit_vars([V|VS], [D|DS]) :-
    get_dict(idType, V, "Internal"),
    !,
    get_dict(variable_name, V, VarName),
    get_dict(dataType, V, VarType),
    convert_type(VarType, KindType),
    get_dict(assignment, V, ValStr),
    string_trim(ValStr, Val),
    format(atom(D), "var ~w : ~w = ~w;", [ VarName, KindType, Val ]),
    implicit_vars(VS, DS).
% TODO: similar to above, but for Mode idType, and Val is modeRequirement.
% However, consider that Kind2 mode support is significantly more complex...
implicit_vars([_|VS], DS) :- implicit_vars(VS, DS).


input_vars(Vars, Decls) :- input_vars_(Vars, _, Decls).
input_vars_([], _, []).
input_vars_([V|VS], [Name|SeenNames], Out) :-
    get_dict(idType, V, "Input"),  % filters out Internal, Mode, and Output vars
    !,
    get_dict(variable_name, V, Name),
    get_dict(dataType, V, VarType),
    convert_type(VarType, KindType),
    format(atom(Decl), '~w:~w', [Name, KindType]),
    input_vars_(VS, SeenNames, DS),
    add_if_not_present(Name, Decl, SeenNames, DS, Out).
input_vars_([_|VS], Seen, Out) :- input_vars_(VS, Seen, Out).


output_vars(Vars, OutNames, Decls) :- output_vars_(Vars, OutNames, _, Decls).
output_vars_(_, [], _, []).
output_vars_(Vars, [VN|VNS], [Name|SeenNames], Out) :-
    find_named_var(VN, Vars, V),
    get_dict(idType, V, "Output"),  % filters out Internal and Mode vars
    !,
    get_dict(variable_name, V, Name),
    get_dict(dataType, V, VarType),
    convert_type(VarType, KindType),
    format(atom(Decl), '~w:~w', [Name, KindType]),
    output_vars_(Vars, VNS, SeenNames, DS),
    add_if_not_present(Name, Decl, SeenNames, DS, Out).
output_vars_(Vars, [_|VNS], Seen, Out) :- output_vars_(Vars, VNS, Seen, Out).

find_named_var(Name, VS, V) :- member(V, VS), get_dict(variable_name, V, Name).

add_if_not_present(_, Decl, [], DS, [Decl|DS]).
add_if_not_present(Var, _, [Var|_], DS, DS) :- !.
add_if_not_present(Var, Decl, [_|VS], DS, Out) :-
    add_if_not_present(Var, Decl, VS, DS, Out).

convert_type("integer", "int").
convert_type("boolean", "bool").

req_vars([], [], []).
req_vars([R|RS], [G|GS], [D|DS]) :-
    get_dict(reqid, R, RID),
    normalize_kind2_var(RID, V),
    get_dict(fulltext, R, FT),
    get_dict(semantics, R, Sem),
    get_dict('CoCoSpecCode', Sem, E),
    format(atom(D), '(* Req: ~w *)~n  var ~w : bool = ~w;~n', [ FT, V, E ]),
    format(atom(G), 'guarantee "~w" ~w;', [RID, V]),
    req_vars(RS, GS, DS).

normalize_kind2_var(Inp, Out) :-
    subst('-', '_', Inp, Out).

%% ----------------------------------------------------------------------

reqs_to_kind2(Vars, CompName, Reqs, CVars, Kind2) :-
    input_vars(Vars, Kind2Input),
    intercalate(Kind2Input, "; ", NodeArgs),
    output_vars(Vars, CVars, Kind2Output),
    intercalate(Kind2Output, "; ", NodeRet),
    implicit_vars(Vars, Kind2Decls),
    intercalate(Kind2Decls, "\n  ", NodeDecls),
    req_vars(Reqs, Kind2Guarantees, Kind2ReqVars),
    intercalate(Kind2ReqVars, "\n  ", NodeReqDecls),
    intercalate(Kind2Guarantees, "\n  ", NodeGuarantees),

    [NodeName, Contracts] = [ CompName, "Contracts here..." ],
    Kind2 = {|string(NodeName, NodeArgs, NodeRet,
                     NodeDecls,
                     NodeReqDecls,
                     NodeGuarantees,
                     Contracts)||
| --Historically
| node H(X:bool) returns (Y:bool);
| let
|     Y = X -> (X and (pre Y));
| tel
|
| --Y since inclusive X
| node SI(X,Y: bool) returns (Z:bool);
| let
| Z = Y and (X or (false -> pre Z));
| tel
|
| --Y since X
| node S(X,Y: bool) returns (Z:bool);
| let
| Z = X or (Y and (false -> pre Z));
| tel
|
| --Once
| node O(X:bool) returns (Y:bool);
| let
|  Y = X or (false -> pre Y);
| tel
|
| --Timed Once: less than or equal to N
| node OTlore( N: int; X: bool) returns (Y: bool);
|     var C:int;
| let
|     C = if X then 0
|         else (-1 -> pre C + (if pre C <0 then 0 else 1));
|
|     Y = 0 <= C and C <= N;
| tel
|
| --Timed Once: general case
| node OT( L: int;  R: int; X: bool) returns (Y: bool);
| var  D:bool;
| let
|   D=delay(X, R);
|   Y=OTlore(L-R, D);
| tel
|
| -- Timed Historically: general case
| node HT( L: int;  R: int; X: bool) returns (Y: bool);
| let
|   Y = not OT(L, R, not X);
| tel
|
| -- Timed Since: general case
| node ST( L: int;  R: int; X: bool; Y: bool)  returns (Z: bool);
| let
|   Z = S(X, Y) and OT(L, R, X);
| tel
|
| -- Timed Since Inclusive: general case
| node SIT( L: int;  R: int; X: bool; Y: bool) returns (Z: bool);
| let
|   Z = SI(X, Y) and OT(L, R, X);
| tel
|
| -- Pre for integers, with an initial value at FTP
| node preInt(InitialValue, X: int) returns (Y:int);
| let
|   Y = InitialValue -> pre X;
| tel
|
| -- Pre for reals, with an initial value at FTP
| node preReal(InitialValue, X: real) returns (Y:real);
| let
|   Y = InitialValue -> pre X;
| tel
|
| -- Pre for booleans, with an initial value at FTP
| node preBool(InitialValue, X: bool) returns (Y:bool);
| let
|   Y = InitialValue -> pre X;
| tel
|
| -- The equivalent of LTL's Y in Lustre.
| node YtoPre(X: bool) returns (Y:bool);
| let
|   Y = false -> pre X;
| tel
|
| -- The equivalent of LTL's Z in Lustre.
| node ZtoPre(X: bool) returns (Y:bool);
| let
|   Y = true -> pre X;
| tel
|
| -- Absolute value for reals
| node absReal(x:real) returns(y: real);
| let
|   y = if (x >= 0.0) then x else -x;
| tel
|
| -- Absolute value for integers
| node absInt(x:int) returns(y: int);
| let
|   y = if (x >= 0) then x else -x;
| tel
|
| -- Maximum value between two reals
| node maxReal (a : real; b : real)
| returns (z : real);
| let
|   z = (if (((a) >= (b))) then (a) else (b));
| tel
|
| -- Maximum value between two integers
| node maxInt (a : int; b : int)
| returns (z : int);
| let
|   z = (if (((a) >= (b))) then (a) else (b));
| tel
|
| -- Minimum value between two integers
| node minInt (a : int; b : int)
| returns (z : int);
| let
|   z = (if (((a) <= (b))) then (a) else (b));
| tel
|
| -- Minimum value between two reals
| node minReal (a : real; b : real)
| returns (z : real);
| let
|   z = (if (((a) <= (b))) then (a) else (b));
| tel
|
| node delay(X:bool;  R:int) returns(Y:bool);
| let
|
|   Y = X;
| tel
|
|
| node imported {NodeName}Spec( {NodeArgs} ) returns ( {NodeRet} );
| (*@contract
|   {NodeDecls}
|
|   {NodeReqDecls}
|
|   {NodeGuarantees}
|
|
| *)
|}.
