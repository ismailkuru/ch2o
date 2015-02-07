(* Copyright (c) 2012-2015, Robbert Krebbers. *)
(* This file is distributed under the terms of the BSD license. *)
Require Export smallstep executable.
Local Opaque listset_singleton.

Section soundness.
Context `{EnvSpec K}.

Lemma assign_exec_correct Γ m a v ass v' va' :
  assign_exec Γ m a v ass = Some (v',va') ↔ assign_sem Γ m a v ass v' va'.
Proof.
  split; [|by destruct 1; simplify_option_equality].
  intros. destruct ass; simplify_option_equality; econstructor; eauto.
Qed.
Lemma ctx_lookup_correct (k : ctx K) x : ctx_lookup x k = get_stack k !! x.
Proof.
  revert x.
  induction k as [|[]]; intros [|x]; f_equal'; rewrite ?list_lookup_fmap; auto.
Qed.
Lemma ehexec_sound Γ k m1 m2 e1 e2 :
  (e2,m2) ∈ ehexec Γ k e1 m1 → Γ\ get_stack k ⊢ₕ e1, m1 ⇒ e2, m2.
Proof.
  intros. destruct e1;
    repeat match goal with
    | H : assign_exec _ _ _ _ _ = Some _ |- _ =>
      apply assign_exec_correct in H
    | _ => progress decompose_elem_of
    | _ => destruct (val_true_false_dec _) as [[[??]|[??]]|[??]]
    | H : ctx_lookup _ _ = _ |- _ => rewrite ctx_lookup_correct in H
    | _ => progress simplify_equality'
    | _ => case_match
    end; do_ehstep.
Qed.
Lemma ehexec_weak_complete Γ k e1 m1 e2 m2 :
  ehexec Γ k e1 m1 ≡ ∅ → ¬Γ\ get_stack k ⊢ₕ e1, m1 ⇒ e2, m2.
Proof.
  destruct 2; 
    repeat match goal with
    | H : assign_sem _ _ _ _ _ _ _ |- _ =>
      apply assign_exec_correct in H
    | H : is_Some _ |- _ => destruct H as [??]
    | _ => progress decompose_empty
    | _ => destruct (val_true_false_dec _ _) as [[[??]|[??]]|[??]]
    | H : get_stack _ !! _ = Some _ |- _ => rewrite <-ctx_lookup_correct in H
    | H : of_option ?o ≫= _ ≡ _, Ho : ?o = Some _ |- _ =>
       rewrite Ho in H; csimpl in H; rewrite collection_bind_singleton in H
    | _ => progress simplify_option_equality
    | _ => case_match
    end; eauto.
Qed.
Lemma ehstep_dec Γ ρ e1 m1 :
  (∃ e2 m2, Γ\ ρ ⊢ₕ e1, m1 ⇒ e2, m2) ∨ ∀ e2 m2, ¬Γ\ ρ ⊢ₕ e1, m1 ⇒ e2, m2.
Proof.
  set (k:=(λ o, @CLocal K o voidT) <$> ρ).
  replace ρ with (get_stack k) by (induction ρ; f_equal'; auto).
  destruct (collection_choose_or_empty (ehexec Γ k e1 m1)) as [[[e2 m2]?]|];
    eauto using ehexec_sound, ehexec_weak_complete.
Qed.
Lemma cexec_sound Γ δ S1 S2 : Γ\ δ ⊢ₛ S1 ⇒ₑ S2 → Γ\ δ ⊢ₛ S1 ⇒ S2.
Proof.
  intros. assert (∀ (k : ctx K) e m,
    ehexec Γ k e m ≡ ∅ → maybe_ECall_redex e = None →
    is_redex e → ¬Γ\ get_stack k ⊢ₕ safe e, m).
  { intros k e m He. rewrite eq_None_not_Some.
    intros Hmaybe Hred Hsafe; apply Hmaybe; destruct Hsafe.
    * eexists; apply maybe_ECall_redex_Some; eauto.
    * edestruct ehexec_weak_complete; eauto. }
  destruct S1;
    repeat match goal with
    | H : _ ∈ ehexec _ _ _ _ |- _ => apply ehexec_sound in H
    | H : _ ∈ expr_redexes _ |- _ =>
      apply expr_redexes_correct in H; destruct H
    | H : maybe2 EVal _ = Some _ |- _ => apply maybe_EVal_Some in H
    | H : maybe_ECall_redex _ = Some _ |- _ =>
      apply maybe_ECall_redex_Some in H; destruct H
    | _ => progress decompose_elem_of
    | _ => case_decide
    | _ => destruct (val_true_false_dec _) as [[[??]|[??]]|[??]]
    | _ => case_match
    | _ => progress simplify_equality'
    end; do_cstep.
Qed.
Lemma cexecs_sound Γ δ S1 S2 : Γ\ δ ⊢ₛ S1 ⇒ₑ* S2 → Γ\ δ ⊢ₛ S1 ⇒* S2.
Proof. induction 1; econstructor; eauto using cexec_sound. Qed.
Lemma cexec_ex_loop Γ δ S :
  ex_loop (λ S1 S2, Γ\ δ ⊢ₛ S1 ⇒ₑ S2) S → ex_loop (cstep Γ δ) S.
Proof.
  revert S; cofix COH; intros S; destruct 1 as [S1 S2 p].
  econstructor; eauto using cexec_sound.
Qed.
End soundness.
