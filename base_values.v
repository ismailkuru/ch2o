(* Copyright (c) 2012-2014, Robbert Krebbers. *)
(* This file is distributed under the terms of the BSD license. *)
Require Export bits.
Local Open Scope cbase_type_scope.

Inductive base_val (Ti : Set) : Set :=
  | VIndet : base_type Ti → base_val Ti
  | VVoid : base_val Ti
  | VInt : int_type Ti → Z → base_val Ti
  | VPtr : ptr Ti → base_val Ti
  | VByte : list (bit Ti) → base_val Ti.
Arguments VIndet {_} _.
Arguments VVoid {_}.
Arguments VInt {_} _ _.
Arguments VPtr {_} _.
Arguments VByte {_} _.

Delimit Scope base_val_scope with B.
Bind Scope base_val_scope with base_val.
Open Scope base_val_scope.
Notation "'voidV'" := VVoid : base_val_scope.
Notation "'indetV' τ" := (VIndet τ) (at level 10) : base_val_scope.
Notation "'intV{' τi } x" := (VInt τi x)
  (at level 10, format "intV{ τi }  x") : base_val_scope.
Notation "'ptrV' p" := (VPtr p) (at level 10) : base_val_scope.
Notation "'byteV' bs" := (VByte bs) (at level 10) : base_val_scope.

Definition maybe_VInt {Ti} (vb : base_val Ti) : option (int_type Ti * Z) :=
  match vb with VInt τi x => Some (τi,x) | _ => None end.
Definition maybe_VPtr {Ti} (vb : base_val Ti) : option (ptr Ti) :=
  match vb with VPtr p => Some p | _ => None end.
Instance base_val_eq_dec {Ti : Set} `{∀ k1 k2 : Ti, Decision (k1 = k2)}
  (v1 v2 : base_val Ti) : Decision (v1 = v2).
Proof. solve_decision. Defined.

Section operations.
  Context `{Env Ti}.

  Record char_byte_valid (Γ : env Ti)
      (Γm : memenv Ti) (bs : list (bit Ti)) : Prop := {
    char_byte_valid_indet : ¬Forall (BIndet =) bs;
    char_byte_valid_bit : ¬(∃ βs, bs = BBit <$> βs);
    char_byte_valid_bits_valid : ✓{Γ,Γm}* bs;
    char_byte_valid_bits : length bs = char_bits
  }.
  Global Instance char_byte_valid_dec Γ Γm bs :
    Decision (char_byte_valid Γ Γm bs).
  Proof.
   refine (cast_if (decide (¬Forall (BIndet =) bs ∧
     ¬(∃ βs, bs = BBit <$> βs) ∧ ✓{Γ,Γm}* bs ∧ length bs = char_bits)));
     abstract (constructor||intros[]; intuition).
  Defined.
  Inductive base_typed' (Γ : env Ti) (Γm : memenv Ti) :
       base_val Ti → base_type Ti → Prop :=
    | VIndet_typed τb : ✓{Γ} τb → τb ≠ voidT → base_typed' Γ Γm (VIndet τb) τb
    | VVoid_typed : base_typed' Γ Γm VVoid voidT
    | VInt_typed x τi : int_typed x τi → base_typed' Γ Γm (VInt τi x) (intT τi)
    | VPtr_typed p τ : (Γ,Γm) ⊢ p : τ → base_typed' Γ Γm (VPtr p) (τ.*)
    | VByte_typed bs :
       char_byte_valid Γ Γm bs → base_typed' Γ Γm (VByte bs) ucharT.
  Global Instance base_typed: Typed (env Ti * memenv Ti)
    (base_type Ti) (base_val Ti) := curry base_typed'.
  Global Instance type_of_base_val: TypeOf (base_type Ti) (base_val Ti) := λ v,
    match v with
    | VIndet τb => τb
    | VVoid => voidT
    | VInt τi _ => intT τi
    | VPtr p => type_of p.*
    | VByte _ => ucharT
    end.
  Global Instance base_type_check:
    TypeCheck (env Ti * memenv Ti) (base_type Ti) (base_val Ti) := λ ΓΓm v,
    match v with
    | VIndet τb => guard (✓{ΓΓm.1} τb); guard (τb ≠ voidT); Some τb
    | VVoid => Some voidT
    | VInt τi x => guard (int_typed x τi); Some (intT τi)
    | VPtr p => TPtr <$> type_check ΓΓm p
    | VByte bs => guard (char_byte_valid (ΓΓm.1) (ΓΓm.2) bs); Some ucharT
    end.
  Global Instance base_val_freeze : Freeze (base_val Ti) := λ β v,
    match v with VPtr p => VPtr (freeze β p) | _ => v end.

  Definition base_val_flatten (Γ : env Ti) (v : base_val Ti) : list (bit Ti) :=
    match v with
    | VIndet τb => replicate (bit_size_of Γ τb) BIndet
    | VVoid => replicate (bit_size_of Γ voidT) BIndet
    | VInt τi x => BBit <$> int_to_bits τi x
    | VPtr p => BPtr <$> ptr_to_bits Γ p
    | VByte bs => bs
    end.
  Definition base_val_unflatten (Γ : env Ti)
      (τb : base_type Ti) (bs : list (bit Ti)) : base_val Ti :=
    match τb with
    | voidT => VVoid
    | intT τi =>
       match mapM maybe_BBit bs with
       | Some βs => VInt τi (int_of_bits τi βs)
       | None =>
          if decide (τi = ucharT%IT ∧ ¬Forall (BIndet =) bs)
          then VByte bs else VIndet τb
       end
    | τ.* => default (VIndet τb) (mapM maybe_BPtr bs ≫= ptr_of_bits Γ τ) VPtr
    end.

  Inductive base_val_refine' (Γ : env Ti)
        (f : meminj Ti) (Γm1 Γm2 : memenv Ti) :
        base_val Ti → base_val Ti → base_type Ti → Prop :=
    | VIndet_refine' τb vb :
       (Γ,Γm2) ⊢ vb : τb → τb ≠ voidT →
       base_val_refine' Γ f Γm1 Γm2 (VIndet τb) vb τb
    | VVoid_refine' : base_val_refine' Γ f Γm1 Γm2 VVoid VVoid voidT
    | VInt_refine' x τi :
       int_typed x τi →
       base_val_refine' Γ f Γm1 Γm2 (VInt τi x) (VInt τi x) (intT τi)
    | VPtr_refine' p1 p2 σ :
       p1 ⊑{Γ,f@Γm1↦Γm2} p2 : σ →
       base_val_refine' Γ f Γm1 Γm2 (VPtr p1) (VPtr p2) (σ.*)
    | VPtr_VIndet_refine p1 vb2 σ :
       (Γ,Γm1) ⊢ p1 : σ → ¬ptr_alive Γm1 p1 →
       (Γ,Γm2) ⊢ vb2 : σ.* → base_val_refine' Γ f Γm1 Γm2 (VPtr p1) vb2 (σ.*)
    | VByte_refine' bs1 bs2 :
       bs1 ⊑{Γ,f@Γm1↦Γm2}* bs2 →
       char_byte_valid Γ Γm1 bs1 → char_byte_valid Γ Γm2 bs2 →
       base_val_refine' Γ f Γm1 Γm2 (VByte bs1) (VByte bs2) ucharT
    | VByte_Vint_refine' bs1 x2 :
       bs1 ⊑{Γ,f@Γm1↦Γm2}* BBit <$> int_to_bits ucharT x2 →
       char_byte_valid Γ Γm1 bs1 → int_typed x2 ucharT →
       base_val_refine' Γ f Γm1 Γm2 (VByte bs1) (VInt ucharT x2) ucharT
    | VByte_VIndet_refine' bs1 bs2 vb2 :
       bs1 ⊑{Γ,f@Γm1↦Γm2}* bs2 → char_byte_valid Γ Γm1 bs1 →
       Forall (BIndet =) bs2 → (Γ,Γm2) ⊢ vb2 : ucharT →
       base_val_refine' Γ f Γm1 Γm2 (VByte bs1) vb2 ucharT.
  Global Instance base_val_refine:
    RefineT Ti (env Ti) (base_type Ti) (base_val Ti) := base_val_refine'.

  Definition base_val_true (Γm : memenv Ti) (vb : base_val Ti) : Prop :=
    match vb with
    | VInt _ x => x ≠ 0
    | VPtr (Ptr a) => index_alive Γm (addr_index a)
    | _ => False
    end.
  Definition base_val_false (vb : base_val Ti) : Prop :=
    match vb with VInt _ x => x = 0 | VPtr (NULL _) => True | _ => False end.
  Definition base_val_0 (τb : base_type Ti) : base_val Ti :=
    match τb with
    | voidT => VVoid | intT τi => VInt τi 0 | τ.* => VPtr (NULL τ)
    end.

  Inductive base_unop_typed : unop → base_type Ti → base_type Ti → Prop :=
    | TInt_NegOp_typed τi :
       base_unop_typed NegOp (intT τi) (intT (int_promote τi))
    | TInt_ComplOp_typed τi :
       base_unop_typed ComplOp (intT τi) (intT (int_promote τi))
    | TInt_NotOp_typed τi :
       base_unop_typed NotOp (intT τi) sintT
    | TPtr_NotOp_typed τ : base_unop_typed NotOp (τ.*) sintT.
  Definition base_unop_type_of (op : unop)
      (τb : base_type Ti) : option (base_type Ti) :=
    match τb, op with
    | intT τi, NotOp => Some sintT
    | intT τi, _ => Some (intT (int_promote τi))
    | τ.*, NotOp => Some sintT
    | _, _ => None
    end.
  Definition base_val_unop_ok (Γm : memenv Ti)
      (op : unop) (vb : base_val Ti) : Prop :=
    match vb, op with
    | VInt τi x, NegOp => int_arithop_ok MinusOp 0 τi x τi
    | VInt τi x, _ => True
    | VPtr p, NotOp => ptr_alive Γm p
    | _, _ => False
    end.
  Global Arguments base_val_unop_ok _ !_ !_ /.
  Definition base_val_unop (op : unop) (vb : base_val Ti) : base_val Ti :=
    match vb, op with
    | VInt τi x, NegOp => VInt (int_promote τi) (int_arithop MinusOp 0 τi x τi)
    | VInt τi x, ComplOp =>
       let τi' := int_promote τi in
       VInt τi' (int_of_bits τi' (negb <$> int_to_bits τi' x))
    | VInt τi x, NotOp => VInt sintT (if decide (x = 0) then 1 else 0)
    | VPtr p, _ => VInt sintT (match p with NULL _ => 1 | Ptr _ => 0 end)
    | _, _ => vb
    end.
  Global Arguments base_val_unop !_ !_ /.

  Inductive base_binop_typed :
        binop → base_type Ti → base_type Ti → base_type Ti → Prop :=
    | CompOp_TInt_TInt_typed op τi1 τi2 :
       base_binop_typed (CompOp op) (intT τi1) (intT τi2) sintT
    | ArithOp_TInt_TInt_typed op τi1 τi2 :
       base_binop_typed (ArithOp op) (intT τi1) (intT τi2)
         (intT (int_promote τi1 ∪ int_promote τi2))
    | ShiftOp_TInt_TInt_typed op τi1 τi2 :
       base_binop_typed (ShiftOp op) (intT τi1) (intT τi2)
         (intT (int_promote τi1))
    | BitOp_TInt_TInt_typed op τi1 τi2 :
       base_binop_typed (BitOp op) (intT τi1) (intT τi2)
         (intT (int_promote τi1 ∪ int_promote τi2))
    | CompOp_TPtr_TPtr_typed c τ :
       base_binop_typed (CompOp c) (τ.*) (τ.*) sintT
    | PlusOp_TPtr_TInt_typed τ σ :
       base_binop_typed (ArithOp PlusOp) (τ.*) (intT σ) (τ.*)
    | PlusOp_VInt_TPtr_typed τ σ :
       base_binop_typed (ArithOp PlusOp) (intT σ) (τ.*) (τ.*)
    | MinusOp_TPtr_TInt_typed τ σi :
       base_binop_typed (ArithOp MinusOp) (τ.*) (intT σi) (τ.*)
    | MinusOp_TInt_TPtr_typed τ σi :
       base_binop_typed (ArithOp MinusOp) (intT σi) (τ.*) (τ.*)
    | MinusOp_TPtr_TPtr_typed τ  :
       base_binop_typed (ArithOp MinusOp) (τ.*) (τ.*) sptrT.
  Definition base_binop_type_of
      (op : binop) (τb1 τb2 : base_type Ti) : option (base_type Ti) :=
    match τb1, τb2, op with
    | intT τi1, intT τi2, CompOp _ => Some sintT
    | intT τi1, intT τi2, (ArithOp _ | BitOp _) =>
       Some (intT (int_promote τi1 ∪ int_promote τi2))
    | intT τi1, intT τi2, ShiftOp _ => Some (intT (int_promote τi1))
    | τ1.*, τ2.*, CompOp _ => guard (τ1 = τ2); Some sintT
    | τ.*, intT σ, (ArithOp PlusOp | ArithOp MinusOp) => Some (τ.*)
    | intT σ, τ.*, (ArithOp PlusOp | ArithOp MinusOp) => Some (τ.*)
    | τ1.*, τ2.*, ArithOp MinusOp => guard (τ1 = τ2); Some sptrT
    | _, _, _ => None
    end.
  Definition base_val_binop_ok (Γ : env Ti) (Γm : memenv Ti)
      (op : binop) (vb1 vb2 : base_val Ti) : Prop :=
    match vb1, vb2, op with
    | VInt τi1 x1, VInt τi2 x2, (CompOp _ | BitOp _) => True
    | VInt τi1 x1, VInt τi2 x2, ArithOp op => int_arithop_ok op x1 τi1 x2 τi2
    | VInt τi1 x1, VInt τi2 x2, ShiftOp op => int_shiftop_ok op x1 τi1 x2 τi2
    | VPtr p1, VPtr p2, CompOp c => ptr_compare_ok Γm c p1 p2
    | VPtr p, VInt _ x, ArithOp PlusOp => ptr_plus_ok Γ Γm x p
    | VInt _ x, VPtr p, ArithOp PlusOp => ptr_plus_ok Γ Γm x p
    | VPtr p, VInt _ x, ArithOp MinusOp => ptr_plus_ok Γ Γm (-x) p
    | VInt _ x, VPtr p, ArithOp MinusOp => ptr_plus_ok Γ Γm (-x) p
    | VPtr p1, VPtr p2, ArithOp MinusOp => ptr_minus_ok Γm p1 p2
    | _, _, _ => False
    end.
  Global Arguments base_val_binop_ok _ _ !_ !_ !_ /.
  Definition base_val_binop (Γ : env Ti)
      (op : binop) (v1 v2 : base_val Ti) : base_val Ti :=
    match v1, v2, op with
    | VInt τi1 x1, VInt τi2 x2, CompOp op =>
       VInt sintT (if Z_comp op x1 x2 then 1 else 0)
    | VInt τi1 x1, VInt τi2 x2, ArithOp op =>
       VInt (int_promote τi1 ∪ int_promote τi2) (int_arithop op x1 τi1 x2 τi2)
    | VInt τi1 x1, VInt τi2 x2, ShiftOp op =>
       VInt (int_promote τi1) (int_shiftop op x1 τi1 x2 τi2)
    | VInt τi1 x1, VInt τi2 x2, BitOp op =>
       let τi' := int_promote τi1 ∪ int_promote τi2 in
       VInt τi' (int_of_bits τi'
         (zip_with (bool_bitop op) (int_to_bits τi' x1) (int_to_bits τi' x2)))
    | VPtr p1, VPtr p2, CompOp c =>
       VInt sintT (if ptr_compare Γ c p1 p2 then 1 else 0)
    | VPtr p, VInt _ i, ArithOp PlusOp => VPtr (ptr_plus Γ i p)
    | VInt _ i, VPtr p, ArithOp PlusOp => VPtr (ptr_plus Γ i p)
    | VPtr p, VInt _ i, ArithOp MinusOp => VPtr (ptr_plus Γ (-i) p)
    | VInt _ i, VPtr p, ArithOp MinusOp => VPtr (ptr_plus Γ (-i) p)
    | VPtr p1, VPtr p2, ArithOp MinusOp => VInt sptrT (ptr_minus Γ p1 p2)
    | _, _, _ => VIndet (type_of v1)
    end.
  Global Arguments base_val_binop _ !_ !_ !_ /.

  Inductive base_cast_typed (Γ : env Ti) :
       base_type Ti → base_type Ti → Prop :=
    | TVoid_cast_typed τb : base_cast_typed Γ τb voidT
    | TInt_cast_typed τi1 τi2 : base_cast_typed Γ (intT τi1) (intT τi2)
    | TPtr_to_TPtr_cast_typed τ : base_cast_typed Γ (τ.*) (τ.*)
    | TPtr_to_void_cast_typed τ : base_cast_typed Γ (τ.*) (voidT.*)
    | TPtr_to_uchar_cast_typed τ : base_cast_typed Γ (τ.*) (ucharT.*)
    | TPtr_of_void_cast_typed τ :
       ptr_type_valid Γ τ → base_cast_typed Γ (voidT.*) (τ.*)
    | TPtr_of_uchar_cast_typed τ :
       ptr_type_valid Γ τ → base_cast_typed Γ (ucharT.*) (τ.*).
  Definition base_val_cast_ok (Γ : env Ti) (Γm : memenv Ti)
      (τb : base_type Ti) (vb : base_val Ti) : Prop :=
    match vb, τb with
    | _, voidT => True
    | VInt _ x, intT τi => int_cast_ok τi x
    | VPtr p, τ.* => ptr_cast_ok Γ Γm τ p
    | VByte _, intT τi => τi = ucharT%IT
    | VIndet τi, intT τi' => τi = ucharT ∧ τi' = ucharT%IT
    | _, _ => False
    end.
  Global Arguments base_val_cast_ok _ _ !_ !_ /.
  Definition base_val_cast (τb : base_type Ti)
      (vb : base_val Ti) : base_val Ti :=
    match vb, τb with
    | _, voidT => VVoid
    | VInt _ x, intT τi => VInt τi (int_cast τi x)
    | VPtr p, τ.* => VPtr (ptr_cast τ p)
    | _ , _ => vb
    end.
  Global Arguments base_val_cast !_ !_ /.
End operations.

Arguments base_val_unflatten _ _ _ _ _ : simpl never.

Section properties.
Context `{EnvSpec Ti}.
Implicit Types Γ : env Ti.
Implicit Types Γm : memenv Ti.
Implicit Types τb : base_type Ti.
Implicit Types vb : base_val Ti.
Implicit Types bs : list (bit Ti).
Implicit Types βs : list bool.

Local Infix "⊑*" := (Forall2 bit_weak_refine) (at level 70).
Hint Extern 0 (_ ⊑* _) => reflexivity.

(** ** General properties of the typing judgment *)
Lemma base_val_typed_type_valid Γ Γm v τb : ✓ Γ → (Γ,Γm) ⊢ v : τb → ✓{Γ} τb.
Proof. destruct 2; try econstructor; eauto using ptr_typed_type_valid. Qed.
Global Instance: TypeOfSpec (env Ti * memenv Ti) (base_type Ti) (base_val Ti).
Proof.
  intros [??]. destruct 1; f_equal'; auto. eapply type_of_correct; eauto.
Qed.
Global Instance:
  TypeCheckSpec (env Ti * memenv Ti) (base_type Ti) (base_val Ti) (λ _, True).
Proof.
  intros [Γ Γmm] vb τb _. split.
  * destruct vb; intros; simplify_option_equality;
      constructor; auto; eapply type_check_sound; eauto.
  * by destruct 1; simplify_option_equality;
      erewrite ?type_check_complete by eauto.
Qed.
Lemma char_byte_valid_weaken Γ1 Γ2 Γm1 Γm2 bs :
  ✓ Γ1 → char_byte_valid Γ1 Γm1 bs → Γ1 ⊆ Γ2 → Γm1 ⊆{⇒} Γm2 →
  char_byte_valid Γ2 Γm2 bs.
Proof. destruct 2; constructor; eauto using Forall_impl, bit_valid_weaken. Qed.
Lemma base_val_typed_weaken Γ1 Γ2 Γm1 Γm2 vb τb :
  ✓ Γ1 → (Γ1,Γm1) ⊢ vb : τb → Γ1 ⊆ Γ2 → Γm1 ⊆{⇒} Γm2 → (Γ2,Γm2) ⊢ vb : τb.
Proof.
  destruct 2; econstructor; eauto using ptr_typed_weaken,
    char_byte_valid_weaken, base_type_valid_weaken.
Qed.
Lemma base_val_frozen_int Γ Γm v τi : (Γ,Γm) ⊢ v : intT τi → frozen v.
Proof. inversion 1; constructor. Qed.
Lemma base_val_freeze_freeze β1 β2 vb : freeze β1 (freeze β2 vb) = freeze β1 vb.
Proof. destruct vb; f_equal'; auto using ptr_freeze_freeze. Qed.
Lemma base_val_freeze_type_of β vb : type_of (freeze β vb) = type_of vb.
Proof. by destruct vb; simpl; rewrite ?ptr_freeze_type_of. Qed.
Lemma base_typed_freeze Γ Γm β vb τb :
  (Γ,Γm) ⊢ freeze β vb : τb ↔ (Γ,Γm) ⊢ vb : τb.
Proof.
  split.
  * destruct vb; inversion 1; constructor; auto.
    by apply (ptr_typed_freeze _ _ β).
  * destruct 1; constructor; auto. by apply ptr_typed_freeze.
Qed.
Lemma base_typed_int_frozen Γ Γm vb τi : (Γ,Γm) ⊢ vb : intT τi → frozen vb.
Proof. inversion_clear 1; constructor. Qed.

(** ** Properties of the [base_val_flatten] function *)
Lemma base_val_flatten_valid Γ Γm vb τb :
  (Γ,Γm) ⊢ vb : τb → ✓{Γ,Γm}* (base_val_flatten Γ vb).
Proof.
  destruct 1; simpl.
  * apply Forall_replicate, BIndet_valid.
  * apply Forall_replicate, BIndet_valid.
  * apply Forall_fmap, Forall_true. constructor.
  * apply Forall_fmap; eapply (Forall_impl (✓{Γ,Γm}));
      eauto using ptr_to_bits_valid, BPtr_valid.
  * eauto using char_byte_valid_bits_valid.
Qed.
Lemma base_val_flatten_weaken Γ1 Γ2 Γm τb vb :
  ✓ Γ1 → (Γ1,Γm) ⊢ vb : τb → Γ1 ⊆ Γ2 →
  base_val_flatten Γ1 vb = base_val_flatten Γ2 vb.
Proof.
  by destruct 2; intros; simpl; erewrite ?ptr_to_bits_weaken,
    ?bit_size_of_weaken by eauto using TBase_valid, TVoid_valid.
Qed.
Lemma base_val_flatten_freeze Γ β vb :
  base_val_flatten Γ (freeze β vb) = base_val_flatten Γ vb.
Proof. by destruct vb; simpl; rewrite ?ptr_to_bits_freeze. Qed.
Lemma base_val_flatten_length Γ Γm vb τb :
  (Γ,Γm) ⊢ vb : τb → length (base_val_flatten Γ vb) = bit_size_of Γ τb.
Proof.
  destruct 1; simplify_equality'.
  * by rewrite replicate_length.
  * by rewrite replicate_length.
  * by rewrite fmap_length, bit_size_of_int, int_to_bits_length.
  * by erewrite fmap_length, ptr_to_bits_length_alt, type_of_correct by eauto.
  * by erewrite bit_size_of_int, int_bits_char, char_byte_valid_bits by eauto.
Qed.

(** ** Properties of the [base_val_unflatten] function *)
Inductive base_val_unflatten_view Γ :
     base_type Ti → list (bit Ti) → base_val Ti → Prop :=
  | base_val_of_void bs : base_val_unflatten_view Γ voidT bs VVoid
  | base_val_of_int τi βs :
     length βs = int_bits τi → base_val_unflatten_view Γ (intT τi)
       (BBit <$> βs) (VInt τi (int_of_bits τi βs))
  | base_val_of_ptr τ p pbs :
     ptr_of_bits Γ τ pbs = Some p →
     base_val_unflatten_view Γ (τ.*) (BPtr <$> pbs) (VPtr p)
  | base_val_of_byte bs :
     length bs = char_bits → ¬Forall (BIndet =) bs →
     ¬(∃ βs, bs = BBit <$> βs) →
     base_val_unflatten_view Γ ucharT bs (VByte bs)
  | base_val_of_byte_indet bs :
     length bs = char_bits → Forall (BIndet =) bs →
     base_val_unflatten_view Γ ucharT bs (VIndet ucharT)
  | base_val_of_int_indet τi bs :
     τi ≠ ucharT%IT →
     length bs = int_bits τi → ¬(∃ βs, bs = BBit <$> βs) →
     base_val_unflatten_view Γ (intT τi) bs (VIndet (intT τi))
  | base_val_of_ptr_indet_1 τ pbs :
     length pbs = bit_size_of Γ (τ.*) → ptr_of_bits Γ τ pbs = None →
     base_val_unflatten_view Γ (τ.*) (BPtr <$> pbs) (VIndet (τ.*))
  | base_val_of_ptr_indet_2 τ bs :
     length bs = bit_size_of Γ (τ.*) → ¬(∃ pbs, bs = BPtr <$> pbs) →
     base_val_unflatten_view Γ (τ.*) bs (VIndet (τ.*)).
Lemma base_val_unflatten_spec Γ τb bs :
  length bs = bit_size_of Γ τb →
  base_val_unflatten_view Γ τb bs (base_val_unflatten Γ τb bs).
Proof.
  intros Hbs. unfold base_val_unflatten. destruct τb as [|τi|τ].
  * constructor.
  * rewrite bit_size_of_int in Hbs.
    destruct (mapM maybe_BBit bs) as [βs|] eqn:Hβs.
    { rewrite maybe_BBits_spec in Hβs; subst. rewrite fmap_length in Hbs.
      by constructor. }
    assert (¬∃ βs, bs = BBit <$> βs).
    { setoid_rewrite <-maybe_BBits_spec. intros [??]; simplify_equality. }
    destruct (decide _) as [[-> ?]|Hτbs].
    { rewrite int_bits_char in Hbs. by constructor. }
    destruct (decide (τi = ucharT%IT)) as [->|?].
    { rewrite int_bits_char in Hbs.
      constructor; auto. apply dec_stable; naive_solver. }
    by constructor.
  * destruct (mapM maybe_BPtr bs) as [pbs|] eqn:Hpbs; csimpl.
    { rewrite maybe_BPtrs_spec in Hpbs; subst. rewrite fmap_length in Hbs.
      by destruct (ptr_of_bits Γ τ pbs) as [p|] eqn:?; constructor. }
    constructor; auto.
    setoid_rewrite <-maybe_BPtrs_spec. intros [??]; simplify_equality.
Qed.
Lemma base_val_unflatten_weaken Γ1 Γ2 τb bs :
  ✓ Γ1 → ✓{Γ1} τb → Γ1 ⊆ Γ2 →
  base_val_unflatten Γ1 τb bs = base_val_unflatten Γ2 τb bs.
Proof.
  intros. unfold base_val_unflatten, default.
  repeat match goal with
    | _ => case_match
    | H : context [ptr_of_bits _ _ _] |- _ =>
      rewrite <-(ptr_of_bits_weaken Γ1 Γ2) in H by eauto using TPtr_valid_inv
    | _ => simplify_option_equality
    end; auto.
Qed.
Lemma base_val_unflatten_int Γ τi βs :
  length βs = int_bits τi →
  base_val_unflatten Γ (intT τi) (BBit <$> βs) = VInt τi (int_of_bits τi βs).
Proof. intro. unfold base_val_unflatten. by rewrite mapM_fmap_Some by done. Qed.
Lemma base_val_unflatten_ptr Γ τ pbs p :
  ptr_of_bits Γ τ pbs = Some p →
  base_val_unflatten Γ (τ.*) (BPtr <$> pbs) = VPtr p.
Proof.
  intros. feed inversion (base_val_unflatten_spec Γ (τ.*) (BPtr <$> pbs));
    simplify_equality'; auto.
  * by erewrite fmap_length, ptr_of_bits_length by eauto.
  * naive_solver (apply Forall_fmap, Forall_true; simpl; eauto).
Qed.
Lemma base_val_unflatten_byte Γ bs :
  ¬Forall (BIndet =) bs → ¬(∃ βs, bs = BBit <$> βs) →
  length bs = char_bits → base_val_unflatten Γ ucharT bs = VByte bs.
Proof.
  intros. feed inversion (base_val_unflatten_spec Γ ucharT bs);
    simplify_equality'; rewrite ?bit_size_of_int, ?int_bits_char; naive_solver.
Qed.
Lemma base_val_unflatten_indet Γ τb bs :
  τb ≠ voidT → Forall (BIndet =) bs → length bs = bit_size_of Γ τb →
  base_val_unflatten Γ τb bs = VIndet τb.
Proof.
  intros. assert (∀ τi βs,
    Forall (@BIndet Ti =) (BBit <$> βs) → length βs ≠ int_bits τi).
  { intros τi βs ??. pose proof (int_bits_pos τi).
    destruct βs; decompose_Forall_hyps; lia. }
  assert (∀ τ pbs p,
    Forall (BIndet =) (BPtr <$> pbs) → ptr_of_bits Γ τ pbs ≠ Some p).
  { intros τ pbs p ??. assert (length pbs ≠ 0).
    { erewrite ptr_of_bits_length by eauto. by apply bit_size_of_base_ne_0. }
    destruct pbs; decompose_Forall_hyps; lia. }
  feed inversion (base_val_unflatten_spec Γ τb bs); naive_solver.
Qed.
Lemma base_val_unflatten_int_indet Γ τi bs :
  τi ≠ ucharT%IT → length bs = int_bits τi → ¬(∃ βs, bs = BBit <$> βs) →
  base_val_unflatten Γ (intT τi) bs = VIndet (intT τi).
Proof.
  intros. feed inversion (base_val_unflatten_spec Γ (intT τi) bs);
    simplify_equality'; rewrite ?bit_size_of_int; naive_solver.
Qed.
Lemma base_val_unflatten_ptr_indet_1 Γ τ pbs :
  length pbs = bit_size_of Γ (τ.*) → ptr_of_bits Γ τ pbs = None →
  base_val_unflatten Γ (τ.*) (BPtr <$> pbs) = VIndet (τ.*).
Proof.
  intros. feed inversion (base_val_unflatten_spec Γ (τ.*) (BPtr <$> pbs));
    simplify_equality'; rewrite ?fmap_length; naive_solver.
Qed.
Lemma base_val_unflatten_ptr_indet_2 Γ τ bs :
  length bs = bit_size_of Γ (τ.*) → ¬(∃ pbs, bs = BPtr <$> pbs) →
  base_val_unflatten Γ (τ.*) bs = VIndet (τ.*).
Proof.
  intros. feed inversion (base_val_unflatten_spec Γ (τ.*) bs);
    simplify_equality'; naive_solver.
Qed.
Lemma base_val_unflatten_indet_elem_of Γ τb bs :
  τb ≠ ucharT → τb ≠ voidT → length bs = bit_size_of Γ τb →
  BIndet ∈ bs → base_val_unflatten Γ τb bs = VIndet τb.
Proof.
  intros ???. feed destruct (base_val_unflatten_spec Γ τb bs);
    rewrite ?elem_of_list_fmap; naive_solver.
Qed.

Lemma base_val_unflatten_typed Γ Γm τb bs :
  ✓{Γ} τb → ✓{Γ,Γm}* bs → length bs = bit_size_of Γ τb →
  (Γ,Γm) ⊢ base_val_unflatten Γ τb bs : τb.
Proof.
  intros. feed destruct (base_val_unflatten_spec Γ τb bs);
    auto; constructor; auto.
  * by apply int_of_bits_typed.
  * eapply ptr_of_bits_typed; eauto using BPtrs_valid_inv.
  * by constructor.
Qed.
Lemma base_val_unflatten_type_of Γ τb bs :
  type_of (base_val_unflatten Γ τb bs) = τb.
Proof.
  unfold base_val_unflatten, default.
  destruct τb; repeat (simplify_option_equality || case_match || intuition).
  f_equal; eauto using ptr_of_bits_type_of.
Qed.
Lemma base_val_unflatten_flatten Γ Γm vb τb :
  (Γ,Γm) ⊢ vb : τb →
  base_val_unflatten Γ τb (base_val_flatten Γ vb) = freeze true vb.
Proof.
  destruct 1 as [τb| |x|p τ|bs []]; simpl.
  * by rewrite base_val_unflatten_indet
      by auto using Forall_replicate_eq, replicate_length.
  * done.
  * by rewrite base_val_unflatten_int, int_of_to_bits
      by auto using int_to_bits_length.
  * by erewrite base_val_unflatten_ptr by eauto using ptr_of_to_bits_typed.
  * by rewrite base_val_unflatten_byte by done.
Qed.
Lemma base_val_unflatten_frozen Γ Γm τb bs :
  ✓{Γ,Γm}* bs → frozen (base_val_unflatten Γ τb bs).
Proof.
  intros. unfold base_val_unflatten, default, frozen.
  destruct τb; repeat (simplify_option_equality || case_match); f_equal'.
  efeed pose proof (λ bs pbs, proj1 (maybe_BPtrs_spec bs pbs)); eauto.
  subst. eapply ptr_of_bits_frozen; eauto using BPtrs_valid_inv.
Qed.
Lemma base_val_flatten_inj Γ Γm β vb1 vb2 τb :
  (Γ,Γm) ⊢ vb1 : τb → (Γ,Γm) ⊢ vb2 : τb →
  base_val_flatten Γ vb1 = base_val_flatten Γ vb2 → freeze β vb1 = freeze β vb2.
Proof.
  intros ?? Hv. by rewrite <-(base_val_freeze_freeze _ true vb1),
    <-(base_val_freeze_freeze _ true vb2),
    <-(base_val_unflatten_flatten Γ Γm vb1 τb),
    <-(base_val_unflatten_flatten Γ Γm vb2 τb), Hv by done.
Qed.
Lemma base_val_flatten_unflatten Γ Γm τb bs :
  ✓{Γ,Γm}* bs → length bs = bit_size_of Γ τb →
  base_val_flatten Γ (base_val_unflatten Γ τb bs) ⊑* bs.
Proof.
  intros. cut (base_val_flatten Γ (base_val_unflatten Γ τb bs) = bs
    ∨ base_val_unflatten Γ τb bs = VIndet τb ∨ τb = voidT).
  { intros [->|[->| ->]]; simpl; eauto using Forall2_replicate_l,
      Forall_true, BIndet_weak_refine, BIndet_valid. }
  feed destruct (base_val_unflatten_spec Γ τb bs); simpl; auto.
  * left. by rewrite int_to_of_bits.
  * left. by erewrite ptr_to_of_bits by eauto using BPtrs_valid_inv.
Qed.
Lemma base_val_flatten_unflatten_char Γ bs :
  length bs = bit_size_of Γ ucharT →
  base_val_flatten Γ (base_val_unflatten Γ ucharT bs) = bs.
Proof.
  intros. feed inversion (base_val_unflatten_spec Γ ucharT bs);
    simplify_equality'; auto using replicate_as_Forall_2.
  by rewrite int_to_of_bits by done.
Qed.
Lemma base_val_unflatten_char_inj Γ bs1 bs2 :
  length bs1 = bit_size_of Γ ucharT → length bs2 = bit_size_of Γ ucharT →
  base_val_unflatten Γ ucharT bs1 = base_val_unflatten Γ ucharT bs2 → bs1 = bs2.
Proof.
  intros ?? Hbs. by rewrite <-(base_val_flatten_unflatten_char Γ bs1),
    <-(base_val_flatten_unflatten_char Γ bs2), Hbs.
Qed.
Lemma base_val_unflatten_between Γ τb bs1 bs2 bs3 :
  ✓{Γ} τb → bs1 ⊑* bs2 → bs2 ⊑* bs3 → length bs1 = bit_size_of Γ τb →
  base_val_unflatten Γ τb bs1 = base_val_unflatten Γ τb bs3 →
  base_val_unflatten Γ τb bs2 = base_val_unflatten Γ τb bs3.
Proof.
  intros ???? Hbs13. destruct (decide (τb = ucharT)) as [->|].
  { apply base_val_unflatten_char_inj in Hbs13; subst;
      eauto using Forall2_length_l.
    by rewrite (anti_symmetric (Forall2 bit_weak_refine) bs2 bs3). }
  destruct (decide (τb = voidT)) as [->|]; [done|].
  destruct (bits_subseteq_eq bs2 bs3) as [->|]; auto.
  rewrite <-Hbs13, !(base_val_unflatten_indet_elem_of Γ);
    eauto using bits_subseteq_indet, Forall2_length_l.
Qed.

(** ** Refinements *)
Lemma base_val_flatten_refine Γ f Γm1 Γm2 vb1 vb2 τb :
  vb1 ⊑{Γ,f@Γm1↦Γm2} vb2 : τb →
  base_val_flatten Γ vb1 ⊑{Γ,f@Γm1↦Γm2}* base_val_flatten Γ vb2.
Proof.
  destruct 1; simpl.
  * apply Forall2_replicate_l; eauto using base_val_flatten_length,
      Forall_impl, base_val_flatten_valid, BIndet_refine.
  * apply Forall2_replicate; repeat constructor.
  * by apply BBits_refine.
  * eapply BPtrs_refine, ptr_to_bits_refine; eauto.
  * eapply BPtrs_BIndets_refine; eauto using ptr_to_bits_valid,
      base_val_flatten_valid, ptr_to_bits_dead.
    by erewrite ptr_to_bits_length, base_val_flatten_length by eauto.
  * done.
  * done.
  * eapply BIndets_refine_r_inv; eauto using base_val_flatten_valid.
    by erewrite base_val_flatten_length, char_byte_valid_bits,
      bit_size_of_int, int_bits_char by eauto.
Qed.
Lemma base_val_refine_typed_l Γ f Γm1 Γm2 vb1 vb2 τb :
  ✓ Γ → vb1 ⊑{Γ,f@Γm1↦Γm2} vb2 : τb → (Γ,Γm1) ⊢ vb1 : τb.
Proof.
  destruct 2; constructor;
    eauto using ptr_refine_typed_l, base_val_typed_type_valid.
Qed.
Lemma base_val_refine_typed_r Γ f Γm1 Γm2 vb1 vb2 τb :
  ✓ Γ → vb1 ⊑{Γ,f@Γm1↦Γm2} vb2 : τb → (Γ,Γm2) ⊢ vb2 : τb.
Proof.
  destruct 2; try constructor; eauto using ptr_refine_typed_r, TInt_valid.
Qed.
Lemma base_val_refine_type_of_l Γ f Γm1 Γm2 vb1 vb2 τb :
  vb1 ⊑{Γ,f@Γm1↦Γm2} vb2 : τb → type_of vb1 = τb.
Proof.
  destruct 1; simplify_type_equality';
    f_equal'; eauto using ptr_refine_type_of_l.
Qed.
Lemma base_val_refine_type_of_r Γ f Γm1 Γm2 vb1 vb2 τb :
  vb1 ⊑{Γ,f@Γm1↦Γm2} vb2 : τb → type_of vb2 = τb.
Proof.
  destruct 1; f_equal'; eauto using ptr_refine_type_of_r, type_of_correct.
Qed.
Lemma base_val_refine_id Γ Γm vb τb : (Γ,Γm) ⊢ vb : τb → vb ⊑{Γ@Γm} vb : τb.
Proof.
  destruct 1; constructor; eauto using ptr_refine_id,
    bits_refine_id, char_byte_valid_bits_valid; constructor; eauto.
Qed.
Lemma base_val_refine_compose Γ f g Γm1 Γm2 Γm3 vb1 vb2 vb3 τb τb' :
  ✓ Γ → vb1 ⊑{Γ,f@Γm1↦Γm2} vb2 : τb → vb2 ⊑{Γ,g@Γm2↦Γm3} vb3 : τb' →
  vb1 ⊑{Γ,f ◎ g@Γm1↦Γm3} vb3 : τb.
Proof.
  intros ? Hvb1 Hvb2. assert (τb = τb') as <- by (eapply (typed_unique _ vb2);
    eauto using base_val_refine_typed_r, base_val_refine_typed_l).
  destruct Hvb1.
  * refine_constructor; eauto using base_val_refine_typed_r.
  * inversion_clear Hvb2; refine_constructor.
  * by inversion_clear Hvb2; refine_constructor.
  * inversion_clear Hvb2; refine_constructor;
      eauto using ptr_refine_compose, ptr_alive_refine, ptr_refine_typed_l.
  * refine_constructor; eauto using base_val_refine_typed_r.
  * inversion_clear Hvb2; refine_constructor; eauto using bits_refine_compose.
  * inversion_clear Hvb2; refine_constructor;
      eauto using BBits_refine, bits_refine_compose.
  * refine_constructor; eauto using base_val_refine_typed_r,
      bits_refine_compose, BIndets_refine, BIndets_valid.
Qed.
Lemma base_val_refine_weaken Γ Γ' f f' Γm1 Γm2 Γm1' Γm2' vb1 vb2 τb :
  ✓ Γ → vb1 ⊑{Γ,f@Γm1↦Γm2} vb2 : τb → Γ ⊆ Γ' → Γm1' ⊑{Γ',f'} Γm2' →
  Γm1 ⊆{⇒} Γm1' → Γm2 ⊆{⇒} Γm2' → meminj_extend f f' Γm1 Γm2 →
  vb1 ⊑{Γ',f'@Γm1'↦Γm2'} vb2 : τb.
Proof.
  destruct 2; refine_constructor; eauto using base_val_typed_weaken,
    ptr_refine_weaken, ptr_typed_weaken, char_byte_valid_weaken,
    ptr_dead_weaken, Forall2_impl, bit_refine_weaken.
Qed.
Lemma base_val_unflatten_refine Γ f Γm1 Γm2 τb bs1 bs2 :
  ✓ Γ → ✓{Γ} τb → bs1 ⊑{Γ,f@Γm1↦Γm2}* bs2 → length bs1 = bit_size_of Γ τb →
  base_val_unflatten Γ τb bs1 ⊑{Γ,f@Γm1↦Γm2} base_val_unflatten Γ τb bs2 : τb.
Proof.
  intros ?? Hbs Hbs1. assert (length bs2 = bit_size_of Γ τb) as Hbs2.
  { eauto using Forall2_length_l. }
  feed destruct (base_val_unflatten_spec Γ τb bs1)
    as [|τi βs1|τ p1 pbs1|bs1|bs1|τi bs1|τ pbs1|τ bs1]; auto.
  * constructor.
  * rewrite (BBits_refine_inv_l Γ f Γm1 Γm2 βs1 bs2),
      base_val_unflatten_int by done.
    constructor. by apply int_of_bits_typed.
  * destruct (decide (ptr_alive Γm1 p1)).
    { destruct (BPtrs_refine_inv_l Γ f Γm1 Γm2 pbs1 bs2) as (pbs2&->&?); auto.
      { erewrite <-ptr_to_of_bits by eauto using BPtrs_valid_inv,
          bits_refine_valid_l; eauto using ptr_to_bits_alive. }
      destruct (ptr_of_bits_refine Γ f Γm1 Γm2 τ pbs1 pbs2 p1)
        as (p2&?&?); eauto.
      erewrite base_val_unflatten_ptr by eauto. by constructor. }
    constructor; eauto using ptr_of_bits_typed, BPtrs_valid_inv,
      bits_refine_valid_l, bits_refine_valid_r, base_val_unflatten_typed.
  * destruct (decide (∃ βs, bs2 = BBit <$> βs)) as [[βs2 ->]|?].
    { rewrite fmap_length, bit_size_of_int in Hbs2.
      rewrite base_val_unflatten_int by done. constructor.
      + by rewrite int_to_of_bits by done.
      + constructor; eauto using bits_refine_valid_l.
      + by apply int_of_bits_typed. }
    assert (length bs2 = char_bits) by eauto using Forall2_length_l.
    destruct (decide (Forall (BIndet =) bs2)).
    { econstructor; eauto using base_val_unflatten_typed, bits_refine_valid_r.
      constructor; eauto using bits_refine_valid_l. }
    rewrite base_val_unflatten_byte by done.
    repeat constructor; eauto using bits_refine_valid_l, bits_refine_valid_r.
  * destruct (decide (∃ βs, bs2 = BBit <$> βs)) as [[βs2 ->]|?].
    { rewrite fmap_length, bit_size_of_int in Hbs2.
      rewrite base_val_unflatten_int by done.
      constructor; [|done]; constructor. by apply int_of_bits_typed. }
    destruct (decide (Forall (BIndet =) bs2)).
    { rewrite base_val_unflatten_indet by done. by repeat constructor. }
    assert (length bs2 = char_bits) by eauto using Forall2_length_l.
    rewrite base_val_unflatten_byte by done.
    repeat constructor; eauto using BIndets_refine_l_inv.
  * destruct (decide (∃ βs, bs2 = BBit <$> βs)) as [[βs2 ->]|?].
    { rewrite fmap_length, bit_size_of_int in Hbs2.
      rewrite base_val_unflatten_int by done.
      repeat constructor; auto; by apply int_of_bits_typed. }
    rewrite bit_size_of_int in Hbs2.
    rewrite base_val_unflatten_int_indet by done. by repeat constructor.
  * constructor; eauto using base_val_unflatten_typed, bits_refine_valid_r.
  * destruct (decide (∃ pbs, bs2 = BPtr <$> pbs)) as [[pbs2 ->]|?].
    { destruct (ptr_of_bits Γ τ pbs2) as [p2|] eqn:?.
      { erewrite base_val_unflatten_ptr by eauto.
        constructor; [|done]; constructor. eauto using ptr_of_bits_typed,
          ptr_of_bits_Exists_Forall_typed, BPtrs_refine_inv_r. }
      rewrite fmap_length in Hbs2.
      rewrite base_val_unflatten_ptr_indet_1 by done.
      by constructor; [|done]; constructor. }
    rewrite base_val_unflatten_ptr_indet_2 by done.
    by constructor; [|done]; constructor.
Qed.

(** ** Properties of unary/binary operations and casts *)
Definition base_val_true_false_dec Γm vb :
  { base_val_true Γm vb ∧ ¬base_val_false vb }
  + { ¬base_val_true Γm vb ∧ base_val_false vb }
  + { ¬base_val_true Γm vb ∧ ¬base_val_false vb }.
Proof.
 refine
  match vb with
  | VInt _ x => inleft (cast_if_not (decide (x = 0)))
  | VPtr (Ptr a) =>
    if decide (index_alive Γm (addr_index a))
    then inleft (left _) else inright _
  | VPtr (NULL _) => inleft (right _)
  | _ => inright _
  end; abstract naive_solver.
Defined.
Lemma base_val_true_weaken Γ Γm1 Γm2 vb :
  base_val_true Γm1 vb → (∀ o, index_alive Γm1 o → index_alive Γm2 o) →
  base_val_true Γm2 vb.
Proof. destruct vb as [| | |[]|]; simpl; auto. Qed.

Global Instance base_val_unop_ok_dec Γm op vb :
  Decision (base_val_unop_ok Γm op vb).
Proof. destruct vb, op; try apply _. Defined.
Global Instance base_val_binop_ok_dec Γ Γm op vb1 vb2 :
  Decision (base_val_binop_ok Γ Γm op vb1 vb2).
Proof.
  destruct vb1, vb2, op as [|op| |]; try apply _; destruct op; apply _.
Defined.
Global Instance base_val_cast_ok_dec Γ Γm σb vb :
  Decision (base_val_cast_ok Γ Γm σb vb).
Proof. destruct vb, σb; apply _. Defined.

Lemma base_unop_typed_type_valid Γ op τb σb :
  base_unop_typed op τb σb → ✓{Γ} τb → ✓{Γ} σb.
Proof. destruct 1; constructor. Qed.
Lemma base_binop_typed_type_valid Γ op τb1 τb2 σb :
  base_binop_typed op τb1 τb2 σb → ✓{Γ} τb1 → ✓{Γ} τb2 → ✓{Γ} σb.
Proof. destruct 1; constructor; eauto using TPtr_valid_inv. Qed.
Lemma base_cast_typed_type_valid Γ τb σb :
  base_cast_typed Γ τb σb → ✓{Γ} τb → ✓{Γ} σb.
Proof. destruct 1; repeat constructor; eauto using TPtr_valid_inv. Qed.
Lemma base_unop_type_of_sound op τb σb :
  base_unop_type_of op τb = Some σb → base_unop_typed op τb σb.
Proof. destruct τb, op; intros; simplify_option_equality; constructor. Qed.
Lemma base_unop_type_of_complete op τb σb :
  base_unop_typed op τb σb → base_unop_type_of op τb = Some σb.
Proof. by destruct 1; simplify_option_equality. Qed.
Lemma base_binop_type_of_sound op τb1 τb2 σb :
  base_binop_type_of op τb1 τb2 = Some σb → base_binop_typed op τb1 τb2 σb.
Proof.
  destruct τb1, τb2, op; intros;
    repeat (case_match || simplify_option_equality); constructor.
Qed.
Lemma base_binop_type_of_complete op τb1 τb2 σb :
  base_binop_typed op τb1 τb2 σb → base_binop_type_of op τb1 τb2 = Some σb.
Proof. by destruct 1; simplify_option_equality. Qed.
Global Instance base_cast_typed_dec Γ τb σb: Decision (base_cast_typed Γ τb σb).
Proof.
 refine
  match τb, σb with
  | _, voidT => left _
  | intT τi1, intT τi2 => left _
  | τ1.*, τ2.* => cast_if (decide (τ1 = τ2 ∨ τ2 = voidT%T ∨ τ2 = ucharT%T ∨
      τ1 = voidT%T ∧ ptr_type_valid Γ τ2 ∨ τ1 = ucharT%T ∧ ptr_type_valid Γ τ2))
  | _, _ => right _
  end; abstract first
    [by intuition; subst; constructor|by inversion 1; naive_solver].
Defined.
Lemma base_cast_typed_weaken Γ1 Γ2 τb σb :
  base_cast_typed Γ1 τb σb → Γ1 ⊆ Γ2 → base_cast_typed Γ2 τb σb.
Proof. destruct 1; constructor; eauto using ptr_type_valid_weaken. Qed.

Lemma base_val_0_typed Γ Γm τb : ✓{Γ} τb → (Γ,Γm) ⊢ base_val_0 τb : τb.
Proof.
  destruct 1; simpl; constructor. by apply int_typed_small. by constructor.
Qed.
Lemma base_val_unop_ok_weaken Γm1 Γm2 op vb :
  base_val_unop_ok Γm1 op vb → (∀ o, index_alive Γm1 o → index_alive Γm2 o) →
  base_val_unop_ok Γm2 op vb.
Proof. destruct vb, op; simpl; eauto using ptr_alive_weaken. Qed.
Lemma base_val_unop_typed Γ Γm op vb τb σb :
  (Γ,Γm) ⊢ vb : τb → base_unop_typed op τb σb →
  base_val_unop_ok Γm op vb → (Γ,Γm) ⊢ base_val_unop op vb : σb.
Proof.
  unfold base_val_unop_ok, base_val_unop. intros Hvτb Hσ Hop.
  destruct Hσ as [τi|?|?|?]; inversion Hvτb; simplify_equality'; try done.
  * typed_constructor. rewrite <-(idempotent (∪) (int_promote τi)).
    apply int_arithop_typed; auto. by apply int_typed_small.
  * typed_constructor. apply int_of_bits_typed.
    by rewrite fmap_length, int_to_bits_length.
  * typed_constructor. by apply int_typed_small; case_decide.
  * typed_constructor. by apply int_typed_small; case_match.
Qed.
Lemma base_val_binop_ok_weaken Γ1 Γ2 Γm1 Γm2 op vb1 vb2 τb1 τb2 :
  ✓ Γ1 → (Γ1,Γm1) ⊢ vb1 : τb1 → (Γ1,Γm1) ⊢ vb2 : τb2 →
  base_val_binop_ok Γ1 Γm1 op vb1 vb2 → Γ1 ⊆ Γ2 →
  (∀ o, index_alive Γm1 o → index_alive Γm2 o) →
  base_val_binop_ok Γ2 Γm2 op vb1 vb2.
Proof.
  destruct 2, 1, op as [|[]| |]; simpl; auto; eauto 2 using
    ptr_plus_ok_weaken, ptr_minus_ok_weaken, ptr_compare_ok_weaken.
Qed.
Lemma base_val_binop_weaken Γ1 Γ2 Γm1 op vb1 vb2 τb1 τb2 :
  ✓ Γ1 → (Γ1,Γm1) ⊢ vb1 : τb1 → (Γ1,Γm1) ⊢ vb2 : τb2 → Γ1 ⊆ Γ2 →
  base_val_binop Γ1 op vb1 vb2 = base_val_binop Γ2 op vb1 vb2.
Proof.
  destruct 2, 1, op as [|[]| |]; intros; f_equal';
    eauto 2 using ptr_plus_weaken, ptr_minus_weaken.
  by erewrite ptr_compare_weaken by eauto.
Qed.
Lemma base_val_binop_typed Γ Γm op vb1 vb2 τb1 τb2 σb :
  ✓ Γ → (Γ,Γm) ⊢ vb1 : τb1 → (Γ,Γm) ⊢ vb2 : τb2 →
  base_binop_typed op τb1 τb2 σb → base_val_binop_ok Γ Γm op vb1 vb2 →
  (Γ,Γm) ⊢ base_val_binop Γ op vb1 vb2 : σb.
Proof.
  unfold base_val_binop_ok, base_val_binop. intros HΓ Hv1τb Hv2τb Hσ Hop.
  revert Hv1τb Hv2τb.
  destruct Hσ; inversion 1; inversion 1; simplify_equality'; try done.
  * constructor. by case_match; apply int_typed_small.
  * constructor. by apply int_arithop_typed.
  * constructor. by apply int_shiftop_typed.
  * constructor. apply int_of_bits_typed.
    rewrite zip_with_length, !int_to_bits_length; lia.
  * constructor. by case_match; apply int_typed_small.
  * constructor. eapply ptr_plus_typed; eauto.
  * constructor. eapply ptr_plus_typed; eauto.
  * constructor. eapply ptr_plus_typed; eauto.
  * constructor. eapply ptr_plus_typed; eauto.
  * constructor. eapply ptr_minus_typed; eauto.
Qed.
Lemma base_cast_typed_self Γ τb : base_cast_typed Γ τb τb.
Proof. destruct τb; constructor. Qed.
Lemma base_val_cast_ok_weaken Γ1 Γ2 Γm1 Γm2 vb τb σb :
  ✓ Γ1 → (Γ1,Γm1) ⊢ vb : τb → base_val_cast_ok Γ1 Γm1 σb vb →
  Γ1 ⊆ Γ2 → (∀ o : index, index_alive Γm1 o → index_alive Γm2 o) →
  base_val_cast_ok Γ2 Γm2 σb vb.
Proof. destruct 2, σb; simpl; eauto using ptr_cast_ok_weaken. Qed.
Lemma base_val_cast_typed Γ Γm vb τb σb :
  ✓ Γ → (Γ,Γm) ⊢ vb : τb → base_cast_typed Γ τb σb →
  base_val_cast_ok Γ Γm σb vb → (Γ,Γm) ⊢ base_val_cast σb vb : σb.
Proof.
  unfold base_val_cast_ok, base_val_cast. intros ? Hvτb Hσb Hok. revert Hvτb.
  destruct Hσb; inversion 1; simplify_equality'; try (done || by constructor).
  * intuition; simplify_equality. by constructor.
  * constructor. by apply int_cast_typed.
  * constructor. eapply ptr_cast_typed,
      TPtr_valid_inv, base_val_typed_type_valid; eauto.
  * constructor.
    eapply ptr_cast_typed; eauto using TBase_ptr_valid, TVoid_valid.
  * constructor. eapply ptr_cast_typed;
      eauto using TBase_ptr_valid, TInt_valid.
  * constructor. eapply ptr_cast_typed; eauto.
  * constructor. eapply ptr_cast_typed; eauto.
Qed.
Lemma base_val_cast_ok_void Γ Γm vb : base_val_cast_ok Γ Γm voidT vb.
Proof. by destruct vb. Qed.
Lemma base_val_cast_void vb : base_val_cast voidT vb = VVoid.
Proof. by destruct vb. Qed.

(** ** Refinements of unary/binary operations and casts *)
Lemma base_val_true_refine Γ f Γm1 Γm2 vb1 vb2 τb :
  vb1 ⊑{Γ,f@Γm1↦Γm2} vb2 : τb → base_val_true Γm1 vb1 → base_val_true Γm2 vb2.
Proof.
   by destruct 1 as [| | |??? []|??? []| | |];
     simpl; eauto using addr_alive_refine.
Qed.
Lemma base_val_false_refine Γ f Γm1 Γm2 vb1 vb2 τb :
  vb1 ⊑{Γ,f@Γm1↦Γm2} vb2 : τb → base_val_false vb1 → base_val_false vb2.
Proof. by destruct 1 as [| | |??? []|??? []| | |]. Qed.
Lemma base_val_unop_ok_refine Γ f Γm1 Γm2 op vb1 vb2 τb :
  vb1 ⊑{Γ,f@Γm1↦Γm2} vb2 : τb →
  base_val_unop_ok Γm1 op vb1 → base_val_unop_ok Γm2 op vb2.
Proof. by destruct op, 1; simpl; eauto using ptr_alive_refine. Qed.
Lemma base_val_unop_refine Γ f Γm1 Γm2 op vb1 vb2 τb σb :
  ✓ Γ → base_unop_typed op τb σb → base_val_unop_ok Γm1 op vb1 →
  vb1 ⊑{Γ,f@Γm1↦Γm2} vb2 : τb →
  base_val_unop op vb1 ⊑{Γ,f@Γm1↦Γm2} base_val_unop op vb2 : σb.
Proof.
  intros ? Hvτb ? Hvb. assert ((Γ,Γm2) ⊢ base_val_unop op vb2 : σb) as Hvb2.
  { eauto using base_val_unop_typed,
      base_val_refine_typed_r, base_val_unop_ok_refine. }
  destruct Hvτb; inversion Hvb as [| | |p1 p2 ? Hp| | | |];
    simplify_equality'; try done.
  * refine_constructor. rewrite <-(idempotent (∪) (int_promote τi)).
    apply int_arithop_typed; auto. by apply int_typed_small.
  * refine_constructor. apply int_of_bits_typed.
    by rewrite fmap_length, int_to_bits_length.
  * refine_constructor. by apply int_typed_small; case_decide.
  * destruct Hp; refine_constructor; by apply int_typed_small.
Qed.
Lemma base_val_binop_ok_refine Γ f Γm1 Γm2 op vb1 vb2 vb3 vb4 τb1 τb3 σb :
  ✓ Γ → base_binop_typed op τb1 τb3 σb →
  vb1 ⊑{Γ,f@Γm1↦Γm2} vb2 : τb1 → vb3 ⊑{Γ,f@Γm1↦Γm2} vb4 : τb3 →
  base_val_binop_ok Γ Γm1 op vb1 vb3 → base_val_binop_ok Γ Γm2 op vb2 vb4.
Proof.
  intros ? Hσ. destruct 1, 1; try done; inversion Hσ;
   try naive_solver eauto using ptr_minus_ok_alive_l, ptr_minus_ok_alive_r,
    ptr_plus_ok_alive, ptr_plus_ok_refine, ptr_minus_ok_refine,
    ptr_compare_ok_refine, ptr_compare_ok_alive_l, ptr_compare_ok_alive_r.
Qed.
Lemma base_val_binop_refine Γ f Γm1 Γm2 op vb1 vb2 vb3 vb4 τb1 τb3 σb :
  ✓ Γ → base_binop_typed op τb1 τb3 σb → base_val_binop_ok Γ Γm1 op vb1 vb3 →
  vb1 ⊑{Γ,f@Γm1↦Γm2} vb2 : τb1 → vb3 ⊑{Γ,f@Γm1↦Γm2} vb4 : τb3 →
  base_val_binop Γ op vb1 vb3 ⊑{Γ,f@Γm1↦Γm2} base_val_binop Γ op vb2 vb4 : σb.
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
Lemma base_val_cast_ok_refine Γ f Γm1 Γm2 vb1 vb2 τb σb :
  ✓ Γ → vb1 ⊑{Γ,f@Γm1↦Γm2} vb2 : τb →
  base_val_cast_ok Γ Γm1 σb vb1 → base_val_cast_ok Γ Γm2 σb vb2.
Proof.
  assert (∀ vb, (Γ,Γm2) ⊢ vb : ucharT → base_val_cast_ok Γ Γm2 ucharT vb).
  { inversion 1; simpl; eauto using int_unsigned_pre_cast_ok,int_cast_ok_more. }
  destruct σb, 2; simpl; try naive_solver eauto using
    ptr_cast_ok_refine, ptr_cast_ok_alive, base_val_cast_ok_void,
    int_unsigned_pre_cast_ok, int_cast_ok_more.
Qed.
Lemma base_val_cast_refine Γ f Γm1 Γm2 vb1 vb2 τb σb :
  ✓ Γ → base_cast_typed Γ τb σb → base_val_cast_ok Γ Γm1 σb vb1 →
  vb1 ⊑{Γ,f@Γm1↦Γm2} vb2 : τb →
  base_val_cast σb vb1 ⊑{Γ,f@Γm1↦Γm2} base_val_cast σb vb2 : σb.
Proof.
  assert (∀ vb, (Γ,Γm2) ⊢ vb : ucharT → base_val_cast ucharT vb = vb) as help.
  { inversion 1; f_equal'. by rewrite int_cast_spec, int_typed_pre_cast
      by eauto using int_unsigned_pre_cast_ok,int_cast_ok_more. }
  destruct 2; inversion 2; simplify_equality'; intuition; simplify_equality'; try first
    [ by exfalso; eauto using ptr_cast_ok_alive
    | rewrite ?base_val_cast_void, ?help, ?int_cast_spec, ?int_typed_pre_cast
        by eauto using int_unsigned_pre_cast_ok,int_cast_ok_more;
      by refine_constructor; eauto using ptr_cast_refine, int_cast_typed,
        ptr_cast_refine, TVoid_valid, TBase_ptr_valid, TInt_valid,
        TPtr_valid_inv, base_val_typed_type_valid, base_val_refine_typed_l ].
Qed.
End properties.
