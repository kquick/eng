% Parses the LTL input text into an AST.

:- module(ltl, [ parse_ltl/2 ]).

:- use_module('../englib').


parse_ltl(Inp, AST) :-
    string_chars(Inp, CS),
    phrase(ltl(AST), CS, R), !,
    ( R == []
    -> true
    ; format('  LTL AST: ~w~n  REMAINDER: ~w~n', [ AST, R ])
    ).


ltl(E) --> boolEx(E).

arithEx(E) --> arithTerm(T), arithExMore(T, E).
%% ltl(expo(E, E)) --> lxm(ltl, E), lxm(expt), lxm(ltl, E).
arithTerm(neg(E)) --> minus(_), lxm(arith, E).
%% ltl(mul(E, E)) --> lxm(ltl, E), lxm(mult), lxm(ltl, E).
%% ltl(div(E, E)) --> lxm(ltl, E), lxm(div), lxm(ltl, E).
%% ltl(mod(E, E)) --> lxm(ltl, E), lxm(mod), lxm(ltl, E).
%% ltl(add(E, E)) --> lxm(ltl, E), lxm(plus), lxm(ltl, E).
%% ltl(sub(E, E)) --> lxm(ltl, E), lxm(minus), lxm(ltl, E).
%% ltl(negfloatnum(M,E)) --> lxm(minus), number(M), ['.'], number(E).
%% ltl(floatnum(M,E)) --> lxm(number, M), ['.'], number(E).
%% ltl(negnum(N)) --> lxm(minus), number(N).
%% ltl(num(N)) --> lxm(number, N).
%% ltl(call(I, Args)) --> lxm(ident, I), args(Args).
arithTerm(id(I)) --> lxm(ident, I).
%% ltl(E) --> boolExpr(E, Ls0, Ls).
%% %% ltl(E) --> boolEx(E).
arithTerm(E) --> lxm(lp), lxm(arithEx, E), lxm(rp).
arithExMore(LT, Expr) --> lxm(expt), arithTerm(E), arithExMore(expo(LT, E), Expr).
arithExMore(LT, LT) --> [].

args([A|MA]) --> lxm(lp), ltl(A), moreArgs(MA), lxm(rp).
%% args([A|MA]) --> lxm(lp), boolExpr(A, Ls0, Ls), moreArgs(MA), lxm(rp).
args([A|MA]) --> lxm(lp), boolEx(A), moreArgs(MA), lxm(rp).
args([A]) --> lxm(lp), ltl(A), lxm(rp).
%% args([A]) --> lxm(lp), boolExpr(A, Ls0, Ls), lxm(rp).
args([A]) --> lxm(lp), boolEx(A), lxm(rp).

moreArgs([A|MA]) --> [','], ltl(A), moreArgs(MA).
moreArgs([A|MA]) --> [','], boolEx(A), moreArgs(MA).
moreArgs([A]) --> [','], ltl(A).
moreArgs([A]) --> [','], boolEx(A).

boolEx(E) --> boolTerm(T), boolExMore(T, E).
% boolTerm(boolcall(I,Args)) --> lxm(ident, I), args(Args). % intercepts others and recurses infinitely
boolTerm(boolid(I)) --> lxm(ident, I).
boolTerm(true) --> lxm(w, "TRUE").
boolTerm(false) --> lxm(w, "FALSE").
boolTerm(ltlH(E)) --> lxm(ltlH), lxm(boolEx, E).
boolTerm(ltlO(E)) --> lxm(ltlO), lxm(boolEx, E).
boolTerm(ltlG(E)) --> lxm(ltlG), lxm(boolEx, E).
boolTerm(ltlF(E)) --> lxm(ltlF), lxm(boolEx, E).
boolTerm(ltlY(E)) --> lxm(ltlY), lxm(boolEx, E).
boolTerm(ltlX(E)) --> lxm(ltlX), lxm(boolEx, E).
boolTerm(ltlZ(E)) --> lxm(ltlZ), lxm(boolEx, E).
boolTerm(ltlBefore(E)) --> lxm(ltlBefore), lxm(boolEx, E).
boolTerm(ltlAfter(E)) --> lxm(ltlAfter), lxm(boolEx, E).
boolTerm(not(E)) --> lxm(not), boolEx(E).
boolTerm(E) --> lxm(lp), lxm(boolEx, E), lxm(rp).
boolTerm(eq(E1,E2)) --> lxm(arithEx, E1), lxm(eq), lxm(arithEx, E2).
boolTerm(le(E1,E2)) --> lxm(arithEx, E1), lxm(le), lxm(arithEx, E2).
boolTerm(ge(E1,E2)) --> lxm(arithEx, E1), lxm(ge), lxm(arithEx, E2).
boolTerm(lt(E1,E2)) --> lxm(arithEx, E1), lxm(lt), lxm(arithEx, E2).
boolTerm(gt(E1,E2)) --> lxm(arithEx, E1), lxm(gt), lxm(arithEx, E2).
boolTerm(neq(E1,E2)) --> lxm(arithEx, E1), lxm(neq), lxm(arithEx, E2).
boolTerm(next(E,E2)) --> lxm(next), boolEx(E), lxm(comma), boolEx(E2).
boolTerm(prev(E,E2)) --> lxm(prev), boolEx(E), lxm(comma), boolEx(E2).
boolExMore(LT, Expr) --> lxm(and), boolTerm(E), boolExMore(and(LT, E), Expr).
boolExMore(LT, Expr) --> lxm(or), boolTerm(E), boolExMore(or(LT, E), Expr).
boolExMore(LT, Expr) --> lxm(xor), boolTerm(E), boolExMore(xor(LT, E), Expr).
boolExMore(LT, Expr) --> lxm(implies), boolTerm(E), boolExMore(implies(LT, E), Expr).
boolExMore(LT, Expr) --> lxm(equiv), boolTerm(E), boolExMore(equiv(LT, E), Expr).

boolExMore(LT, Expr) --> lxm(ltlSI), lxm(bound, B), boolTerm(E),
                         boolExMore(binSI_bound(B, LT, E), Expr).
boolExMore(LT, Expr) --> lxm(ltlSI), boolTerm(E),
                         boolExMore(binSI(LT, E), Expr).
boolExMore(LT, Expr) --> lxm(ltlS), lxm(bound, B), boolTerm(E),
                         boolExMore(binS_bound(B, LT, E), Expr).
boolExMore(LT, Expr) --> lxm(ltlS), boolTerm(E),
                         boolExMore(binS(LT, E), Expr).
boolExMore(LT, Expr) --> lxm(ltlT), lxm(bound, B), boolTerm(E),
                         boolExMore(binT_bound(B, LT, E), Expr).
boolExMore(LT, Expr) --> lxm(ltlT), boolTerm(E),
                         boolExMore(binT(LT, E), Expr).
boolExMore(LT, Expr) --> lxm(ltlUI), lxm(bound, B), boolTerm(E),
                         boolExMore(binUI_bound(B, LT, E), Expr).
boolExMore(LT, Expr) --> lxm(ltlUI), boolTerm(E),
                         boolExMore(binUI(LT, E), Expr).
boolExMore(LT, Expr) --> lxm(ltlU), lxm(bound, B), boolTerm(E),
                         boolExMore(binU_bound(B, LT, E), Expr).
boolExMore(LT, Expr) --> lxm(ltlU), boolTerm(E),
                         boolExMore(binU(LT, E), Expr).
boolExMore(LT, Expr) --> lxm(ltlV), lxm(bound, B), boolTerm(E),
                         boolExMore(binV_bound(B, LT, E), Expr).
boolExMore(LT, Expr) --> lxm(ltlV), boolTerm(E),
                         boolExMore(binV(LT, E), Expr).
boolExMore(LT, LT) --> [].


bound(range2(B,E)) --> ['['], ltl(B), [','], ltl(E), [']'].
bound(range1(B)) --> ['['], ltl(B), [']'].
bound(salt_eq(E)) --> lxm(eq), lxm(ltl, E).
bound(salt_le(E)) --> lxm(le), lxm(ltl, E).
bound(salt_ge(E)) --> lxm(ge), lxm(ltl, E).
bound(salt_lt(E)) --> lxm(lt), lxm(ltl, E).
bound(salt_gt(E)) --> lxm(gt), lxm(ltl, E).
bound(salt_neq(E)) --> lxm(eq), lxm(ltl, E).

comma() --> [ ',' ].
lp() --> [ '(' ].
rp() --> [ ')' ].
expt() --> [ '^' ].
mult() --> [ '*' ].
div() --> [ '/' ].
plus() --> [ '+' ].
minus(m) --> [ '-' ].
not() --> [ '!' ].
and() --> [ '&' ].
or() --> [ '|' ].
xor() --> [ 'x', 'o', 'r' ].
xor() --> [ 'X', 'o', 'r' ].
xor() --> [ 'x', 'O', 'R' ].
xor() --> [ 'x', 'O', 'r' ].
xor() --> [ 'X', 'O', 'R' ].
mod() --> [ 'm', 'o', 'd' ].
mod() --> [ 'M', 'o', 'd' ].
mod() --> [ 'M', 'O', 'D' ].
eq() --> [ '=' ].
lt() --> [ '<' ].
gt() --> [ '>' ].
neq() --> [ '!', '=' ].
le() --> [ '<', '=' ].
ge() --> [ '>', '=' ].
implies() --> [ '-', '>' ].
equiv() --> [ '<', '-', '>' ].
next() --> lxm(w, "at"), lxm(w, "the"), lxm(w, "next"),
           lxm(w, "occurrence"), lxm(w, "of").
prev() --> lxm(w, "at"), lxm(w, "the"), lxm(w, "previous"),
           lxm(w, "occurrence"), lxm(w, "of").
ltlH() --> [ 'H' ].
ltlO() --> [ 'O' ].
ltlG() --> [ 'G' ].
ltlF() --> [ 'F' ].
ltlSI() --> [ 'S', 'I' ].
ltlS() --> [ 'S' ].
ltlT() --> [ 'T' ].
ltlUI() --> [ 'U', 'I' ].
ltlU() --> [ 'U' ].
ltlV() --> [ 'V' ].
ltlY() --> [ 'Y' ].
ltlX() --> [ 'X' ].
ltlZ() --> [ 'Z' ].
ltlBefore() --> [ '<', '|' ].
ltlAfter() --> [ '|', '>' ].


ident(I) --> w(I).  % Ident should allow $ and should not start with a numeric

lxm(R) --> ws_, { ! }, lxm(R).
lxm(R) --> call(R).

lxm(R, P) --> ws_, { ! }, lxm(R, P).
lxm(R, P) --> call(R, P).

lxm(R, O, P) --> ws_, { ! }, lxm(R, O, P).
lxm(R, O, P) --> call(R, O, P).

lxm(R, O, U, P) --> ws_, { ! }, lxm(R, O, U, P).
lxm(R, O, U, P) --> call(R, O, U, P).

%% wsp(P) --> ws(A), ws(B), { pos(A,B,P) }.
%% wsp(P) --> ws(P).

ws_() --> [C], { char_type(C, space) }.

w(W) --> [C], { wchar(C) }, w_(CS), { string_chars(W, [C|CS]) }.
w_([C|CS]) --> [C], { wchar(C) }, !, w_(CS).
w_([]) --> [].

wchar(C) :- \+ char_type(C, space),
            % Exclude things that might be individual tokens needing to be
            % recognized elsewhere in the grammar.
            \+ member(C, ['(', ')', '.', '!', '?', ':', ',',
                          %% '{', '}', '^', '[', ']', %% XXX?
                          '$',
                          '/']).
