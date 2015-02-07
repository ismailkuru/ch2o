(* Copyright (c) 2012-2015, Robbert Krebbers. *)
(* This file is distributed under the terms of the BSD license. *)
(** The small step reduction (as defined in the file [smallstep]) traverses
through the program in small steps by moving the focus on the substatement
that is being executed. Uses of non-local control ([goto] and [return]) are
performed in small steps rather than in big steps as well. *)

(** In order to model the concept of focusing on the substatement that is being
executed, this file defines program contexts as an extension of Huet's zipper
data structure. Program contexts extend the zipper data structure by annotating
each block scope variable with its associated memory index, and they furthermore
contain the full call stack of the program. Program contexts can also be seen
as a generalization of continuations (as for example being used in CompCert).
However, there are some notable differences.

- Program contexts implicitly contain the stack, whereas a continuation
  semantics typically stores the stack separately.
- Program contexts also contain the part of the program that has been
  executed, whereas continuations only contain the part that remains to be done.
- Since the complete program is preserved, looping constructs (e.g. while and
  for) do not have to duplicate code.

The fact that program contexts do not throw away the parts of the statement
that have been executed is essential for our treatment of goto. Upon an
invocation of a goto, the semantics traverses through the program context until
the corresponding label has been found. During this traversal it passes all
block scope variables that went out of scope, allowing it to perform required
allocations and deallocations in a natural way. Hence, the point of this
traversal is not so much to search for the label, but much more to incrementally
calculate the required allocations and deallocations. *)

(** In a continuation semantics, upon the use of a goto, one typically computes,
or looks up, the statement and continuation corresponding to the target label.
However, it is not very natural to reconstruct the required allocations and
deallocations from the current and target continuations. *)
Require Import String stringmap mapset.
Require Export expressions.

(** * Labels and gotos *)
(** We use the type [N] of binary natural numbers for labels, and the
implementation [Nmap] for efficient finite sets, and finite maps indexed by
labels. We define type classes [Gotos] and [Labels] to collect the labels of
gotos respectively the labels of labeled statements. *)
Definition labelname := string.
Definition labelmap := stringmap.
Notation labelset := (mapset (labelmap unit)).

Instance labelname_dec: ∀ i1 i2 : labelname, Decision (i1 = i2) := decide_rel (=).
Instance labelname_inhabited: Inhabited labelname := populate ""%string.
Instance labelmap_dec {A} `{∀ a1 a2 : A, Decision (a1 = a2)} :
  ∀ m1 m2 : labelmap A, Decision (m1 = m2) := decide_rel (=).
Instance labelmap_empty {A} : Empty (labelmap A) := @empty (stringmap A) _.
Instance labelmap_lookup {A} : Lookup labelname A (labelmap A) :=
  @lookup _ _ (stringmap A) _.
Instance labelmap_partial_alter {A} : PartialAlter labelname A (labelmap A) :=
  @partial_alter _ _ (stringmap A) _.
Instance labelmap_to_list {A} : FinMapToList labelname A (labelmap A) :=
  @map_to_list _ _ (stringmap A) _.
Instance labelmap_omap: OMap labelmap := @omap stringmap _.
Instance labelmap_merge: Merge labelmap := @merge stringmap _.
Instance labelmap_fmap: FMap labelmap := @fmap stringmap _.
Instance: FinMap labelname labelmap := _.
Instance labelmap_dom {A} : Dom (labelmap A) labelset := mapset_dom.
Instance: FinMapDom labelname labelmap labelset := mapset_dom_spec.

Typeclasses Opaque labelname labelmap.

Class Gotos A := gotos: A → labelset.
Arguments gotos {_ _} !_ / : simpl nomatch.
Class Labels A := labels: A → labelset.
Arguments labels {_ _} !_ / : simpl nomatch.

(** * Statements *)
(** The construct [SDo e] executes the expression [e] and ignores the result.
The construct [SLocal τ s] opens a new scope with one variable of type τ. Since
we use De Bruijn indexes for variables, it does not contain the name of the
variable. *)
Inductive stmt (K : Set) : Set :=
  | SDo : expr K → stmt K
  | SSkip : stmt K
  | SGoto : labelname → stmt K
  | SThrow : nat → stmt K
  | SReturn : expr K → stmt K
  | SLabel : labelname → stmt K
  | SLocal : type K → stmt K → stmt K
  | SCatch : stmt K → stmt K
  | SComp : stmt K → stmt K → stmt K
  | SLoop : stmt K → stmt K
  | SIf : expr K → stmt K → stmt K → stmt K.
Notation funenv K := (funmap (stmt K)).

Instance stmt_eq_dec {K : Set} `{∀ k1 k2 : K, Decision (k1 = k2)}
  (s1 s2 : stmt K) : Decision (s1 = s2).
Proof. solve_decision. Defined.

(** We use the scope [stmt_scope] for notations of statements. *)
Delimit Scope stmt_scope with S.
Bind Scope stmt_scope with stmt.
Open Scope stmt_scope.

Arguments SDo {_} _.
Arguments SSkip {_}.
Arguments SGoto {_} _%string.
Arguments SThrow {_} _.
Arguments SReturn {_} _.
Arguments SLabel {_} _.
Arguments SLocal {_} _ _%S.
Arguments SCatch {_} _.
Arguments SComp {_}_%S _%S.
Arguments SLoop {_} _%S.
Arguments SIf {_} _ _%S _%S.

Notation "! e" := (SDo e) (at level 10) : stmt_scope.
Notation "'skip'" := SSkip : stmt_scope.
Notation "'goto' l" := (SGoto l) (at level 10) : stmt_scope.
Notation "'throw' n" := (SThrow n) (at level 10) : stmt_scope.
Notation "'ret' e" := (SReturn e) (at level 10) : stmt_scope.
Notation "'label' l" := (SLabel l) (at level 10) : stmt_scope.
Notation "'local{' τ } s" := (SLocal τ s)
  (at level 10, format "'local{' τ }  s") : stmt_scope.
Notation "'catch' s" := (SCatch s) (at level 10) : stmt_scope.
Notation "s1 ;; s2" := (SComp s1 s2)
  (at level 80, right associativity,
   format "'[' s1  ;;  '/' s2 ']'") : stmt_scope.
Notation "'loop' s" := (SLoop s)
  (at level 10, format "'loop'  s") : stmt_scope.
Notation "'if{' e } s1 'else' s2" := (SIf e s1 s2)
  (at level 56, format "if{ e }  s1  'else'  s2") : stmt_scope.
Notation "l :; s" := (label l ;; s)
  (at level 80, format "l  :;  s") : stmt_scope.
Notation "e1 ::={ ass } e2" := (!(e1 ::={ass} e2))
  (at level 54, format "e1  ::={ ass }  e2", right associativity) : stmt_scope.
Notation "e1 ::= e2" := (!(e1 ::= e2))
  (at level 54, right associativity) : stmt_scope.
Notation "'call' f @ es" := (!(call f @ es))
  (at level 10, es at level 66) : stmt_scope.
Notation "'free' e" := (!(free e)) (at level 10) : stmt_scope.

Instance: Injective (=) (=) (@SDo K).
Proof. by injection 1. Qed.
Instance: Injective (=) (=) (@SGoto K).
Proof. by injection 1. Qed.
Instance: Injective (=) (=) (@SReturn K).
Proof. by injection 1. Qed.
Instance: Injective2 (=) (=) (=) (@SLocal K).
Proof. by injection 1. Qed.

Instance stmt_gotos {K} : Gotos (stmt K) :=
  fix go s := let _ : Gotos _ := @go in
  match s with
  | ! _ | skip | throw _ | ret _ | label _ => ∅
  | goto l => {[ l ]}
  | local{_} s | catch s | loop s => gotos s
  | s1 ;; s2 | if{_} s1 else s2 => gotos s1 ∪ gotos s2
  end.
Instance stmt_labels {K} : Labels (stmt K) :=
  fix go s := let _ : Labels _ := @go in
  match s with
  | ! _ | skip | goto _ | throw _ | ret _ => ∅
  | label l => {[ l ]}
  | catch s | local{_} s | loop s => labels s
  | s1 ;; s2 | if{_} s1 else s2 => labels s1 ∪ labels s2
  end.
Instance stmt_locks {K} : Locks (stmt K) :=
  fix go s := let _ : Locks _ := @go in
  match s with
  | ! e | ret e => locks e
  | skip | throw _ | goto _ | label _=> ∅
  | catch s | local{_} s | loop s => locks s
  | s1 ;; s2 => locks s1 ∪ locks s2
  | if{e} s1 else s2 => locks e ∪ locks s1 ∪ locks s2
  end.
Fixpoint throws_valid {K} (n : nat) (s : stmt K) : Prop :=
  match s with
  | !_ | ret _ | skip | goto _ | label _ => True
  | throw i => i < n
  | local{_} s | loop s => throws_valid n s
  | catch s => throws_valid (S n) s
  | s1 ;; s2 | if{_} s1 else s2 => throws_valid n s1 ∧ throws_valid n s2
  end.
Instance throws_valid_dec {K} : ∀ n (s : stmt K), Decision (throws_valid n s).
Proof.
 refine (
  fix go n s :=
  match s return Decision (throws_valid n s) with
  | !_ | ret _ | skip | goto _ | label _ => left _
  | throw i => cast_if (decide (i < n))
  | local{_} s | loop s => go n s
  | catch s => go (S n) s
  | s1 ;; s2 | if{_} s1 else s2 => cast_if_and (go n s1) (go n s2)
  end); clear go; abstract naive_solver.
Defined.

(** * Program contexts *)
(** We first define the data type [sctx_item] of singular statement contexts. A
pair [(E, s)] consisting of a list of singular statement contexts [E] and a
statement [s] forms a zipper for statements without block scope variables. *)
Inductive sctx_item (K : Set) : Set :=
  | CCatch : sctx_item K
  | CCompL : stmt K → sctx_item K
  | CCompR : stmt K → sctx_item K
  | CLoop : sctx_item K
  | CIfL : expr K → stmt K → sctx_item K
  | CIfR : expr K → stmt K → sctx_item K.

Instance sctx_item_eq_dec {K : Set} `{∀ k1 k2 : K, Decision (k1 = k2)}
  (E1 E2 : sctx_item K) : Decision (E1 = E2).
Proof. solve_decision. Defined.

Arguments CCatch {_}.
Arguments CCompL {_} _.
Arguments CCompR {_} _.
Arguments CLoop {_}.
Arguments CIfL {_} _ _.
Arguments CIfR {_} _ _.

Bind Scope stmt_scope with sctx_item.
Notation "'catch' □" := CCatch (at level 10, format "catch  □") : stmt_scope.
Notation "□ ;; s" := (CCompL s) (at level 80, format "□  ;;  s") : stmt_scope.
Notation "s ;; □" := (CCompR s) (at level 80, format "s  ;;  □") : stmt_scope.
Notation "'loop' □" := CLoop (at level 10, format "'loop'  □") : stmt_scope.
Notation "'if{' e } □ 'else' s2" := (CIfL e s2)
  (at level 56, format "if{ e }  □  'else'  s2") : stmt_scope.
Notation "'if{' e } s1 'else' □" := (CIfR e s1)
  (at level 56, format "if{ e }  s1  'else'  □") : stmt_scope.

Instance sctx_item_subst {K} :
    Subst (sctx_item K) (stmt K) (stmt K) := λ Es s,
  match Es with
  | catch □ => catch s
  | □ ;; s2 => s ;; s2
  | s1 ;; □ => s1 ;; s
  | loop □ => loop s
  | if{e} □ else s2 => if{e} s else s2
  | if{e} s1 else □ => if{e} s1 else s
  end.
Instance: DestructSubst (@sctx_item_subst K).

Instance: ∀ Es : sctx_item K, Injective (=) (=) (subst Es).
Proof. destruct Es; repeat intro; simpl in *; by simplify_equality. Qed.

Instance sctx_item_gotos {K} : Gotos (sctx_item K) := λ Es,
  match Es with
  | catch □ | loop □ => ∅
  | s ;; □ | □ ;; s  | if{_} □ else s | if{_} s else □ => gotos s
  end.
Instance sctx_item_labels {K} : Labels (sctx_item K) := λ Es,
  match Es with
  | catch □ | loop □ => ∅
  | s ;; □ | □ ;; s | if{_} □ else s | if{_} s else □ => labels s
  end.
Instance sctx_item_locks {K} : Locks (sctx_item K) := λ Es,
  match Es with
  | □ ;; s | s ;; □ => locks s
  | catch □ | loop □ => ∅
  | if{e} □ else s | if{e} s else □ => locks e ∪ locks s
  end.

Lemma sctx_item_subst_gotos {K} (Es : sctx_item K) (s : stmt K) :
  gotos (subst Es s) = gotos Es ∪ gotos s.
Proof. apply elem_of_equiv_L. intros. destruct Es; solve_elem_of. Qed.
Lemma sctx_item_subst_labels {K} (Es : sctx_item K) (s : stmt K) :
  labels (subst Es s) = labels Es ∪ labels s.
Proof. apply elem_of_equiv_L. intros. destruct Es; solve_elem_of. Qed.
Lemma sctx_item_subst_locks {K} (Es : sctx_item K) (s : stmt K) :
  locks (subst Es s) = locks Es ∪ locks s.
Proof. apply elem_of_equiv_L. destruct Es; esolve_elem_of. Qed.

(** Next, we define the data type [esctx_item] of expression in statement
contexts. These contexts are used to store the statement to which an expression
that is being executed belongs to. *)
Inductive esctx_item (K : Set) : Set :=
  | CDoE : esctx_item K
  | CReturnE : esctx_item K
  | CIfE : stmt K → stmt K → esctx_item K.

Instance esctx_item_eq_dec {K : Set} `{∀ k1 k2 : K, Decision (k1 = k2)}
  (Ee1 Ee2 : esctx_item K) : Decision (Ee1 = Ee2).
Proof. solve_decision. Defined.

Arguments CDoE {_}.
Arguments CReturnE {_}.
Arguments CIfE {_} _ _.
Notation "! □" := CDoE (at level 10, format "!  □") : stmt_scope.
Notation "'ret' □" := CReturnE (at level 10, format "'ret'  □") : stmt_scope.
Notation "'if{' □ } s1 'else' s2" := (CIfE s1 s2)
  (at level 56, format "if{ □ }  s1  'else'  s2") : stmt_scope.

Instance esctx_item_subst {K} :
    Subst (esctx_item K) (expr K) (stmt K) := λ Ee e,
  match Ee with
  | ! □ => ! e
  | ret □ => ret e
  | if{□} s1 else s2 => if{e} s1 else s2
  end.
Instance: DestructSubst (@esctx_item_subst K).

Instance: ∀ Ee : esctx_item K, Injective (=) (=) (subst Ee).
Proof. destruct Ee; intros ???; simpl in *; by simplify_equality. Qed.

Instance esctx_item_gotos {K} : Gotos (esctx_item K) := λ Ee,
  match Ee with
  | ! □ | ret □ => ∅
  | if{□} s1 else s2 => gotos s1 ∪ gotos s2
  end.
Instance esctx_item_labels {K} : Labels (esctx_item K) := λ Ee,
  match Ee with
  | ! □ | ret □ => ∅
  | if{□} s1 else s2 => labels s1 ∪ labels s2
  end.
Instance esctx_item_locks {K} : Locks (esctx_item K) := λ Ee,
  match Ee with
  | ! □  | ret □ => ∅
  | if{□} s1 else s2 => locks s1 ∪ locks s2
  end.

Lemma esctx_item_subst_gotos {K} (Ee : esctx_item K) (e : expr K) :
  gotos (subst Ee e) = gotos Ee.
Proof. apply elem_of_equiv_L. intros. destruct Ee; solve_elem_of. Qed.
Lemma esctx_item_subst_labels {K} (Ee : esctx_item K) (e : expr K) :
  labels (subst Ee e) = labels Ee.
Proof. apply elem_of_equiv_L. intros. destruct Ee; solve_elem_of. Qed.
Lemma esctx_item_subst_locks {K} (Ee : esctx_item K) (e : expr K) :
  locks (subst Ee e) = locks Ee ∪ locks e.
Proof. apply elem_of_equiv_L. destruct Ee; esolve_elem_of. Qed.

(** Finally, we define the type [ctx_item] to extends [sctx_item] with some
additional singular contexts. These contexts will be used as follows.

- When entering a block, [local{τ} s], the context [CLocal b τ] is appended to
  the head of the program context. It associates the block scope variable with
  its corresponding memory index [b].
- To execute a statement [subst E e] containing an expression [e], the context
  [CExpr e E] is appended to the head of the program context. It stores the
  expression [e] itself and its location [E]. The expression itself is needed
  to restore the statement when execution of the expression is finished. The
  location is needed to determine what to do with the result of the expression.
- Upon a function call, [subst E (call f @ vs)], the context [CFun E] is
  appended to the head of the program context. It contains the location [E]
  of the caller so that it can be restored when the called function [f] returns.
- When a function body is entered, the context [CParams bs] is appended to the
  head of the program context. It contains a list of memory indexes of the
  function parameters.

Program contexts [ctx] are then defined as lists of singular contexts. *)
Inductive ctx_item (K : Set) : Set :=
  | CStmt : sctx_item K → ctx_item K
  | CLocal : index → type K → ctx_item K
  | CExpr : expr K → esctx_item K → ctx_item K
  | CFun : ectx K → ctx_item K
  | CParams : funname → list (index * type K) → ctx_item K.
Notation ctx K := (list (ctx_item K)).

Arguments CStmt {_} _.
Arguments CLocal {_} _ _.
Arguments CExpr {_} _ _.
Arguments CFun {_} _.
Arguments CParams {_} _ _.

Instance ctx_item_eq_dec {K : Set} `{∀ k1 k2 : K, Decision (k1 = k2)}
  (Ek1 Ek2 : ctx_item K) : Decision (Ek1 = Ek2).
Proof. solve_decision. Defined.

Instance ctx_item_locks {K} : Locks (ctx_item K) := λ Ek,
  match Ek with
  | CStmt Es => locks Es
  | CExpr e Ee => locks e ∪ locks Ee
  | CFun E => locks E
  | _ => ∅
  end.

(** Given a context, we can construct a stack using the following erasure
function. We define [get_stack (CFun _ :: k)] as [[]] instead of [getstack k],
as otherwise it would be possible to refer to the local variables of the
caller. *)
Fixpoint get_stack {K} (k : ctx K) : stack :=
  match k with
  | [] => []
  | CStmt _ :: k | CExpr _ _ :: k => get_stack k
  | CLocal o τ :: k => o :: get_stack k
  | CFun _ :: _ => []
  | CParams _ oτs :: _ => fst <$> oτs
  end.
Fixpoint get_stack_types {K} (k : ctx K) : list (type K) :=
  match k with
  | [] => []
  | CStmt _ :: k | CExpr _ _ :: k => get_stack_types k
  | CLocal o τ :: k => τ :: get_stack_types k
  | CFun _ :: _ => []
  | CParams _ oτs :: _ => snd <$> oτs
  end.
Instance ctx_free_gotos {K} : Gotos (ctx K) :=
  fix go k := let _ : Gotos _ := @go in
  match k with
  | CStmt Es :: k => gotos Es ∪ gotos k
  | CLocal _ _ :: k => gotos k
  | CExpr _ E :: k => gotos E ∪ gotos k
  | _ => ∅
  end.
Instance ctx_free_labels {K} : Labels (ctx K) :=
  fix go k := let _ : Labels _ := @go in
  match k with
  | CStmt Es :: k => labels Es ∪ labels k
  | CLocal _ _ :: k => labels k
  | CExpr _ E :: k => labels E ∪ labels k
  | _ => ∅
  end.
Fixpoint ctx_catches {K} (k : ctx K) : nat :=
  match k with
  | CStmt (catch □) :: k => S (ctx_catches k)
  | (CStmt _ | CLocal _ _) :: k => ctx_catches k
  | _ => 0
  end.

Lemma get_stack_app {K} (k1 k2 k3 : ctx K) :
  get_stack k2 = get_stack k3 → get_stack (k1 ++ k2) = get_stack (k1 ++ k3).
Proof. induction k1 as [|[] ?]; intros; simpl; auto with f_equal. Qed.
