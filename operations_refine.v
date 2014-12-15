(* Copyright (c) 2012-2014, Robbert Krebbers. *)
(* This file is distributed under the terms of the BSD license. *)
Require Export operations values_refine.
Require Import pointer_casts.
Local Open Scope ctype_scope.

Section operations.
Context `{EnvSpec Ti}.
Implicit Types Γ : env Ti.
Implicit Types Γm : memenv Ti.
Implicit Types τb σb : base_type Ti.
Implicit Types τ σ : type Ti.
Implicit Types a : addr Ti.
Implicit Types vb : base_val Ti.
Implicit Types v : val Ti.
Implicit Types m : mem Ti.
Hint Immediate index_alive_1'.
Hint Resolve ptr_alive_1' index_alive_2'.

(** ** Refinements of operations on addresses *)
Lemma addr_plus_ok_refine Γ α f m1 m2 a1 a2 σ j :
  a1 ⊑{Γ,α,f@'{m1}↦'{m2}} a2 : σ →
  addr_plus_ok Γ m1 j a1 → addr_plus_ok Γ m2 j a2.
Proof.
  unfold addr_plus_ok. intros Ha (?&?&?).
  destruct (addr_byte_refine_help Γ α f
    ('{m1}) ('{m2}) a1 a2 σ) as (i&?&?); auto.
  destruct Ha as [??????????? []]; simplify_equality'; split; eauto; lia.
Qed.
Lemma addr_plus_refine Γ α f m1 m2 a1 a2 σ j :
  ✓ Γ → addr_plus_ok Γ m1 j a1 → a1 ⊑{Γ,α,f@'{m1}↦'{m2}} a2 : σ →
  addr_plus Γ j a1 ⊑{Γ,α,f@'{m1}↦'{m2}} addr_plus Γ j a2 : σ.
Proof.
  intros ? Ha' Ha. destruct Ha' as (_&?&?), Ha as
    [o o' r r' r'' i i'' τ τ' σ σc ??????????? Hr'']; simplify_equality'.
  econstructor; eauto.
  { apply Nat2Z.inj_le. by rewrite Nat2Z.inj_mul, Z2Nat.id by done. }
  { apply Nat2Z.inj. rewrite Z2Nat_inj_mod, Z2Nat.id by done.
    rewrite Z.mod_add, <-Z2Nat_inj_mod; auto with f_equal.
    rewrite (Nat2Z.inj_iff _ 0).
    eauto using size_of_ne_0, ref_typed_type_valid, castable_type_valid. }
  destruct Hr'' as [i|r i]; simplify_equality'; [|by constructor].
  apply ref_refine_nil_alt; auto. rewrite ref_offset_freeze.
  rewrite Nat2Z.inj_add, Nat2Z.inj_mul. 
  transitivity (Z.to_nat ((i + j * size_of Γ σc) +
    size_of Γ σ * ref_offset r')); [f_equal; lia |].
  by rewrite Z2Nat.inj_add, Z2Nat.inj_mul, !Nat2Z.id
    by auto using Z.mul_nonneg_nonneg with lia.
Qed.
Lemma addr_minus_ok_refine Γ α f m1 m2 a1 a2 a3 a4 σ :
  a1 ⊑{Γ,α,f@'{m1}↦'{m2}} a2 : σ → a3 ⊑{Γ,α,f@'{m1}↦'{m2}} a4 : σ →
  addr_minus_ok m1 a1 a3 → addr_minus_ok m2 a2 a4.
Proof.
  destruct 1 as [??????????? [] ?????????? []],
    1 as [??????????? [] ?????????? []];
    intros (?&?&Hr); simplify_equality'; eauto.
  rewrite !fmap_app, !ref_freeze_freeze by eauto; eauto with congruence.
Qed.
Lemma addr_minus_refine Γ α f m1 m2 a1 a2 a3 a4 σ :
  addr_minus_ok m1 a1 a3 → a1 ⊑{Γ,α,f@'{m1}↦'{m2}} a2 : σ →
  a3 ⊑{Γ,α,f@'{m1}↦'{m2}} a4 : σ → addr_minus Γ a1 a3 = addr_minus Γ a2 a4.
Proof.
  intros (?&?&?).
  destruct 1 as [o1 o2 r1 r2 r3 i1 i3 τ1 τ2 σ1 σc ??????????? Hr3],
    1 as [o4 o5 r4 r5 r6 i4 i6 τ4 τ5 σ3 σc4 ??????????? Hr6].
  destruct Hr3, Hr6; simplify_type_equality'; f_equal; lia.
Qed.
Lemma addr_cast_ok_refine Γ α f m1 m2 a1 a2 σ σc :
  ✓ Γ → a1 ⊑{Γ,α,f@'{m1}↦'{m2}} a2 : σ →
  addr_cast_ok Γ m1 σc a1 → addr_cast_ok Γ m2 σc a2.
Proof.
  destruct 2 as [o o' r r' r'' i i'' τ τ' σ σc' [] ?????????? []];
    intros (?&?&?); simplify_equality'; split_ands; eauto.
  destruct (castable_divide Γ σ σc) as [z ->]; auto. rewrite ref_offset_freeze.
  destruct (decide (size_of Γ σc = 0)) as [->|?]; [done|].
  by rewrite !(Nat.mul_comm (_ * size_of _ _)), Nat.mul_assoc, Nat.mod_add.
Qed.
Lemma addr_cast_refine Γ α f m1 m2 a1 a2 σ σc :
  addr_cast_ok Γ m1 σc a1 → a1 ⊑{Γ,α,f@'{m1}↦'{m2}} a2 : σ →
  addr_cast σc a1 ⊑{Γ,α,f@'{m1}↦'{m2}} addr_cast σc a2 : σc.
Proof. intros (?&?&?). destruct 1; simplify_equality'; econstructor; eauto. Qed.
Lemma addr_elt_refine Γ α f Γm1 Γm2 a1 a2 rs σ σ' :
  ✓ Γ → a1 ⊑{Γ,α,f@Γm1↦Γm2} a2 : σ → addr_strict Γ a1 → Γ ⊢ rs : σ ↣ σ' →
  ref_seg_offset rs = 0 →
  addr_elt Γ rs a1 ⊑{Γ,α,f@Γm1↦Γm2} addr_elt Γ rs a2 : σ'.
Proof.
  intros ? [o o' r r' r'' i i'' τ τ' σ'' ??????????? Hcst Hr''] ? Hrs ?; simpl.
  apply castable_alt in Hcst; destruct Hcst as [<-|[?|?]];
    simplify_equality'; try solve [inversion Hrs].
  erewrite path_type_check_complete by eauto; simpl. econstructor; eauto.
  * apply ref_typed_cons; exists σ''; split; auto.
    apply ref_set_offset_typed; auto.
    apply Nat.div_lt_upper_bound; eauto using size_of_ne_0,ref_typed_type_valid.
  * lia.
  * by rewrite Nat.mod_0_l by eauto using size_of_ne_0, ref_typed_type_valid,
      ref_seg_typed_type_valid, castable_type_valid.
  * destruct Hr'' as [i''|]; simplify_equality'; [|by constructor].
    apply ref_refine_ne_nil_alt.
    by rewrite ref_set_offset_set_offset, (Nat.mul_comm (size_of _ _)),
      Nat.div_add, Nat.div_small, Nat.add_0_l, ref_set_offset_offset by lia.
Qed.

(** ** Refinements of operations on pointers *)
Lemma ptr_alive_refine' Γ α f m1 m2 p1 p2 σ :
  ptr_alive' m1 p1 → p1 ⊑{Γ,α,f@'{m1}↦'{m2}} p2 : σ → ptr_alive' m2 p2.
Proof. destruct 2; simpl in *; eauto using addr_alive_refine. Qed.
Lemma ptr_compare_ok_refine Γ α f m1 m2 c p1 p2 p3 p4 σ :
  p1 ⊑{Γ,α,f@'{m1}↦'{m2}} p2 : σ → p3 ⊑{Γ,α,f@'{m1}↦'{m2}} p4 : σ →
  ptr_compare_ok m1 c p1 p3 → ptr_compare_ok m2 c p2 p4.
Proof.
  destruct 1, 1, c; simpl; eauto using addr_minus_ok_refine, addr_alive_refine.
Qed.
Lemma ptr_compare_refine Γ α f m1 m2 c p1 p2 p3 p4 σ :
  ✓ Γ → ptr_compare_ok m1 c p1 p3 →
  p1 ⊑{Γ,α,f@'{m1}↦'{m2}} p2 : σ → p3 ⊑{Γ,α,f@'{m1}↦'{m2}} p4 : σ →
  ptr_compare Γ c p1 p3 = ptr_compare Γ c p2 p4.
Proof.
  destruct 3, 1, c; simpl; done || by erewrite addr_minus_refine by eauto.
Qed.
Lemma ptr_plus_ok_refine Γ α f m1 m2 p1 p2 σ j :
  p1 ⊑{Γ,α,f@'{m1}↦'{m2}} p2 : σ →
  ptr_plus_ok Γ m1 j p1 → ptr_plus_ok Γ m2 j p2.
Proof. destruct 1; simpl; eauto using addr_plus_ok_refine. Qed.
Lemma ptr_plus_refine Γ α f m1 m2 p1 p2 σ j :
  ✓ Γ → ptr_plus_ok Γ m1 j p1 → p1 ⊑{Γ,α,f@'{m1}↦'{m2}} p2 : σ →
  ptr_plus Γ j p1 ⊑{Γ,α,f@'{m1}↦'{m2}} ptr_plus Γ j p2 : σ.
Proof. destruct 3; simpl; constructor; eauto using addr_plus_refine. Qed.
Lemma ptr_minus_ok_refine Γ α f m1 m2 p1 p2 p3 p4 σ :
  p1 ⊑{Γ,α,f@'{m1}↦'{m2}} p2 : σ → p3 ⊑{Γ,α,f@'{m1}↦'{m2}} p4 : σ →
  ptr_minus_ok m1 p1 p3 → ptr_minus_ok m2 p2 p4.
Proof. destruct 1, 1; simpl; eauto using addr_minus_ok_refine. Qed.
Lemma ptr_minus_refine Γ α f m1 m2 p1 p2 p3 p4 σ :
  ✓ Γ → ptr_minus_ok m1 p1 p3 →
  p1 ⊑{Γ,α,f@'{m1}↦'{m2}} p2 : σ → p3 ⊑{Γ,α,f@'{m1}↦'{m2}} p4 : σ →
  ptr_minus Γ p1 p3 = ptr_minus Γ p2 p4.
Proof. destruct 3, 1; simpl; eauto using addr_minus_refine. Qed.
Lemma ptr_cast_ok_refine Γ α f m1 m2 p1 p2 σ σc :
  ✓ Γ → p1 ⊑{Γ,α,f@'{m1}↦'{m2}} p2 : σ →
  ptr_cast_ok Γ m1 σc p1 → ptr_cast_ok Γ m2 σc p2.
Proof. destruct 2; simpl; eauto using addr_cast_ok_refine. Qed.
Lemma ptr_cast_refine Γ α f m1 m2 p1 p2 σ σc :
  ptr_cast_ok Γ m1 σc p1 → ptr_type_valid Γ σc →
  p1 ⊑{Γ,α,f@'{m1}↦'{m2}} p2 : σ →
  ptr_cast σc p1 ⊑{Γ,α,f@'{m1}↦'{m2}} ptr_cast σc p2 : σc.
Proof. destruct 3; constructor; eauto using addr_cast_refine. Qed.

(** ** Refinements of operations on base values *)
Lemma base_val_true_refine Γ α f m1 m2 vb1 vb2 τb :
  vb1 ⊑{Γ,α,f@'{m1}↦'{m2}} vb2 : τb →
  base_val_true m1 vb1 → base_val_true m2 vb2.
Proof.
  destruct 1 as [| | | |??? []|???? []| | |];
    naive_solver eauto 10 using addr_alive_refine.
Qed.
Lemma base_val_false_refine Γ α f Γm1 Γm2 vb1 vb2 τb :
  vb1 ⊑{Γ,α,f@Γm1↦Γm2} vb2 : τb → base_val_false vb1 → base_val_false vb2.
Proof. by destruct 1 as [| | | |??? []|???? []| | |]. Qed.
Lemma base_val_unop_ok_refine Γ α f m1 m2 op vb1 vb2 τb :
  vb1 ⊑{Γ,α,f@'{m1}↦'{m2}} vb2 : τb →
  base_val_unop_ok m1 op vb1 → base_val_unop_ok m2 op vb2.
Proof. destruct op, 1; naive_solver eauto using ptr_alive_refine'. Qed.
Lemma base_val_unop_refine Γ α f m1 m2 op vb1 vb2 τb σb :
  ✓ Γ → base_unop_typed op τb σb → base_val_unop_ok m1 op vb1 →
  vb1 ⊑{Γ,α,f@'{m1}↦'{m2}} vb2 : τb →
  base_val_unop op vb1 ⊑{Γ,α,f@'{m1}↦'{m2}} base_val_unop op vb2 : σb.
Proof.
  intros ? Hvτb ? Hvb. assert ((Γ,'{m2}) ⊢ base_val_unop op vb2 : σb) as Hvb2.
  { eauto using base_val_unop_typed,
      base_val_refine_typed_r, base_val_unop_ok_refine. }
  destruct Hvτb; inversion Hvb as [| | | |p1 p2 ? Hp| | | |];
    simplify_equality'; try done.
  * refine_constructor. rewrite <-(idempotent_L (∪) (int_promote τi)).
    apply int_arithop_typed; auto. by apply int_typed_small.
  * refine_constructor. apply int_of_bits_typed.
    by rewrite fmap_length, int_to_bits_length.
  * refine_constructor. by apply int_typed_small; case_decide.
  * destruct Hp; refine_constructor; by apply int_typed_small.
  * naive_solver.
Qed.
Lemma base_val_binop_ok_refine Γ α f m1 m2 op vb1 vb2 vb3 vb4 τb1 τb3 σb :
  ✓ Γ → base_binop_typed op τb1 τb3 σb →
  vb1 ⊑{Γ,α,f@'{m1}↦'{m2}} vb2 : τb1 → vb3 ⊑{Γ,α,f@'{m1}↦'{m2}} vb4 : τb3 →
  base_val_binop_ok Γ m1 op vb1 vb3 → base_val_binop_ok Γ m2 op vb2 vb4.
Proof.
  intros ? Hσ. destruct 1, 1; try done; inversion Hσ;
   try naive_solver eauto using ptr_minus_ok_alive_l, ptr_minus_ok_alive_r,
    ptr_plus_ok_alive, ptr_plus_ok_refine, ptr_minus_ok_refine,
    ptr_compare_ok_refine, ptr_compare_ok_alive_l, ptr_compare_ok_alive_r.
Qed.
Lemma base_val_binop_refine Γ α f m1 m2 op vb1 vb2 vb3 vb4 τb1 τb3 σb :
  ✓ Γ → base_binop_typed op τb1 τb3 σb → base_val_binop_ok Γ m1 op vb1 vb3 →
  vb1 ⊑{Γ,α,f@'{m1}↦'{m2}} vb2 : τb1 → vb3 ⊑{Γ,α,f@'{m1}↦'{m2}} vb4 : τb3 →
  base_val_binop Γ op vb1 vb3
    ⊑{Γ,α,f@'{m1}↦'{m2}} base_val_binop Γ op vb2 vb4 : σb.
Proof.
  intros ? Hσ ?; destruct 1, 1; try done; inversion Hσ; simplify_equality';
    try first
    [ by refine_constructor; eauto using int_arithop_typed,
        int_arithop_typed, int_shiftop_typed, ptr_plus_refine
    | exfalso; by eauto using ptr_minus_ok_alive_l, ptr_minus_ok_alive_r,
        ptr_plus_ok_alive, ptr_compare_ok_alive_l, ptr_compare_ok_alive_r ].
  * refine_constructor. by case_match; apply int_typed_small.
  * refine_constructor. apply int_of_bits_typed.
    rewrite zip_with_length, !int_to_bits_length; lia.
  * erewrite ptr_compare_refine by eauto.
    refine_constructor. by case_match; apply int_typed_small.
  * erewrite ptr_minus_refine by eauto. refine_constructor.
    eapply ptr_minus_typed; eauto using ptr_refine_typed_l, ptr_refine_typed_r.
Qed.
Lemma base_val_cast_ok_refine Γ α f m1 m2 vb1 vb2 τb σb :
  ✓ Γ → vb1 ⊑{Γ,α,f@'{m1}↦'{m2}} vb2 : τb →
  base_val_cast_ok Γ m1 σb vb1 → base_val_cast_ok Γ m2 σb vb2.
Proof.
  assert (∀ vb, (Γ,'{m2}) ⊢ vb : ucharT%BT → base_val_cast_ok Γ m2 ucharT vb).
  { inversion 1; simpl; eauto using int_unsigned_pre_cast_ok,int_cast_ok_more. }
  destruct σb, 2; simpl; try naive_solver eauto using
    ptr_cast_ok_refine, ptr_cast_ok_alive, base_val_cast_ok_void,
    int_unsigned_pre_cast_ok, int_cast_ok_more, ptr_alive_refine'.
Qed.
Lemma base_val_cast_refine Γ α f m1 m2 vb1 vb2 τb σb :
  ✓ Γ → base_cast_typed Γ τb σb → base_val_cast_ok Γ m1 σb vb1 →
  vb1 ⊑{Γ,α,f@'{m1}↦'{m2}} vb2 : τb →
  base_val_cast σb vb1 ⊑{Γ,α,f@'{m1}↦'{m2}} base_val_cast σb vb2 : σb.
Proof.
  assert (∀ vb,
    (Γ,'{m2}) ⊢ vb : ucharT%BT → base_val_cast ucharT vb = vb) as help.
  { inversion 1; f_equal'. by rewrite int_cast_spec, int_typed_pre_cast
      by eauto using int_unsigned_pre_cast_ok,int_cast_ok_more. }
  destruct 2; inversion 2;
    simplify_equality'; intuition; simplify_equality'; try first
    [ by exfalso; eauto using ptr_cast_ok_alive
    | rewrite ?base_val_cast_void, ?help, ?int_cast_spec, ?int_typed_pre_cast
        by eauto using int_unsigned_pre_cast_ok,int_cast_ok_more;
      by refine_constructor; eauto using ptr_cast_refine, int_cast_typed,
        ptr_cast_refine, TVoid_valid, TBase_ptr_valid, TInt_valid,
        TPtr_valid_inv, base_val_typed_type_valid, base_val_refine_typed_l ].
Qed.

(** ** Refinements of operations on values *)
Lemma val_true_refine Γ α f m1 m2 v1 v2 τ :
  v1 ⊑{Γ,α,f@'{m1}↦'{m2}} v2 : τ → val_true m1 v1 → val_true m2 v2.
Proof. destruct 1; simpl; eauto using base_val_true_refine. Qed.
Lemma val_false_refine Γ α f Γm1 Γm2 v1 v2 τ :
  v1 ⊑{Γ,α,f@Γm1↦Γm2} v2 : τ → val_false v1 → val_false v2.
Proof. destruct 1; simpl; eauto using base_val_false_refine. Qed.
Lemma val_true_false_refine Γ α f m1 m2 v1 v2 τ :
  val_true m1 v1 → val_false v2 → v1 ⊑{Γ,α,f@'{m1}↦'{m2}} v2 : τ → False.
Proof.
  intros. by destruct (val_true_false_dec m2 v2)
    as [[[??]|[??]]|[??]]; eauto using val_true_refine.
Qed.
Lemma val_false_true_refine Γ α f m1 m2 v1 v2 τ :
  val_false v1 → val_true m2 v2 → v1 ⊑{Γ,α,f@'{m1}↦'{m2}} v2 : τ → False.
Proof.
  intros. by destruct (val_true_false_dec m2 v2)
    as [[[??]|[??]]|[??]]; eauto using val_false_refine.
Qed.
Lemma val_true_refine_inv Γ α f m1 m2 v1 v2 τ :
  v1 ⊑{Γ,α,f@'{m1}↦'{m2}} v2 : τ → val_true m2 v2 →
  val_true m1 v1 ∨ (α ∧ ¬val_true m1 v1 ∧ ¬val_false v1).
Proof.
  intros. destruct α.
  * destruct (val_true_false_dec m1 v1) as [[[??]|[??]]|[??]];
      naive_solver eauto using val_false_true_refine.
  * eauto using val_true_refine, val_refine_inverse.
Qed.
Lemma val_false_refine_inv Γ α f m1 m2 v1 v2 τ :
  v1 ⊑{Γ,α,f@'{m1}↦'{m2}} v2 : τ → val_false v2 →
  val_false v1 ∨ (α ∧ ¬val_true m1 v1 ∧ ¬val_false v1).
Proof.
  intros. destruct α.
  * destruct (val_true_false_dec m1 v1) as [[[??]|[??]]|[??]];
      naive_solver eauto using val_true_false_refine.
  * eauto using val_false_refine, val_refine_inverse.
Qed.
Lemma val_unop_ok_refine Γ α f m1 m2 op v1 v2 τ :
  v1 ⊑{Γ,α,f@'{m1}↦'{m2}} v2 : τ →
  val_unop_ok m1 op v1 → val_unop_ok m2 op v2.
Proof. destruct op, 1; simpl; eauto using base_val_unop_ok_refine. Qed.
Lemma val_unop_refine Γ α f m1 m2 op v1 v2 τ σ :
  ✓ Γ → unop_typed op τ σ → val_unop_ok m1 op v1 →
  v1 ⊑{Γ,α,f@'{m1}↦'{m2}} v2 : τ →
  val_unop op v1 ⊑{Γ,α,f@'{m1}↦'{m2}} val_unop op v2 : σ.
Proof.
  destruct 2; inversion 2; intros; simplify_equality';
    refine_constructor; eauto using base_val_unop_refine.
Qed.
Lemma val_binop_ok_refine Γ α f m1 m2 op v1 v2 v3 v4 τ1 τ3 σ :
  ✓ Γ → binop_typed op τ1 τ3 σ →
  v1 ⊑{Γ,α,f@'{m1}↦'{m2}} v2 : τ1 → v3 ⊑{Γ,α,f@'{m1}↦'{m2}} v4 : τ3 →
  val_binop_ok Γ m1 op v1 v3 → val_binop_ok Γ m2 op v2 v4.
Proof.
  unfold val_binop_ok; destruct 2; do 2 inversion 1;
    simplify_equality'; eauto using base_val_binop_ok_refine.
Qed.
Lemma val_binop_refine Γ α f m1 m2 op v1 v2 v3 v4 τ1 τ3 σ :
  ✓ Γ → binop_typed op τ1 τ3 σ → val_binop_ok Γ m1 op v1 v3 →
  v1 ⊑{Γ,α,f@'{m1}↦'{m2}} v2 : τ1 → v3 ⊑{Γ,α,f@'{m1}↦'{m2}} v4 : τ3 →
  val_binop Γ op v1 v3 ⊑{Γ,α,f@'{m1}↦'{m2}} val_binop Γ op v2 v4 : σ.
Proof.
  destruct 2; intro; do 2 inversion 1; simplify_equality';
    refine_constructor; eauto using base_val_binop_refine.
Qed.
Lemma val_cast_ok_refine Γ α f m1 m2 v1 v2 τ σ :
  ✓ Γ → v1 ⊑{Γ,α,f@'{m1}↦'{m2}} v2 : τ →
  val_cast_ok Γ m1 σ v1 → val_cast_ok Γ m2 σ v2.
Proof.
  unfold val_cast_ok; destruct σ, 2; eauto using base_val_cast_ok_refine.
Qed.
Lemma val_cast_refine Γ α f m1 m2 v1 v2 τ σ :
  ✓ Γ → cast_typed Γ τ σ → val_cast_ok Γ m1 σ v1 →
  v1 ⊑{Γ,α,f@'{m1}↦'{m2}} v2 : τ →
  val_cast σ v1 ⊑{Γ,α,f@'{m1}↦'{m2}} val_cast σ v2 : σ.
Proof.
  destruct 2; inversion 2; simplify_equality; repeat refine_constructor;
    eauto using base_val_cast_refine, TVoid_cast_typed, base_cast_typed_self.
Qed.
End operations.