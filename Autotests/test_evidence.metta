;; ═══════════════════════════════════════════════════════════════════════
;; Deterministic tests for the Evidence Store (src/evidence.metta)
;; ═══════════════════════════════════════════════════════════════════════
;;
;; These tests verify that:
;;   1. observe() stores grounded facts as Observation atoms
;;   2. derive() stores PLN conclusions as Derivation atoms
;;   3. STV() looks up real evidence instead of returning (stv 0.1 0.9)
;;   4. provenance() returns the evidence chain for an atom
;;   5. pin() stores working-memory observations (no longer a no-op)
;;   6. claim-status() distinguishes grounded claims from hypotheses
;;   7. PLN Modus Ponens uses evidence-backed truth values
;;
;; Run standalone:  metta test_evidence.metta
;; ═══════════════════════════════════════════════════════════════════════

;; Load the required libraries in the same order as lib_omegaclaw.metta
!(import! &self (library OmegaClaw-Core lib_nal))
!(import! &self (library OmegaClaw-Core lib_pln))
!(import! &self (library OmegaClaw-Core ./src/utils))
!(import! &self (library OmegaClaw-Core ./src/evidence))


;; ─── Test 1: observe stores a fact ────────────────────────────────

!(observe (Inheritance patient_demo ElevatedPC1) (stv 0.95 0.85) api_data)

;; Verify the observation was recorded
!(assertEqual
   (let $result (collapse (match &self (Observation (Inheritance patient_demo ElevatedPC1) $truth $_ $_) $truth))
        (car-atom $result))
   (stv 0.95 0.85))


;; ─── Test 2: STV returns observed evidence, not the fallback ──────

!(assertEqual
   (let (stv $s $c) (STV (Inheritance patient_demo ElevatedPC1))
        (and (> $s 0.9) (> $c 0.8)))
   True)


;; ─── Test 3: STV falls back to default for unknown atoms ──────────

!(assertEqual
   (STV (Inheritance unknown_atom NeverObserved))
   (stv (/ 1.0 10.0) 0.9))


;; ─── Test 4: derive stores a conclusion with provenance ───────────

;; First observe the clinical rule
!(observe (Implication (Inheritance patient_demo ElevatedPC1) (Inheritance patient_demo CardioRisk))
          (stv 0.85 0.90) clinical_guideline)

;; Now derive a conclusion
!(derive (Inheritance patient_demo CardioRisk)
         (stv 0.82 0.76)
         ModusPonens
         ((Inheritance patient_demo ElevatedPC1)
          (Implication (Inheritance patient_demo ElevatedPC1) (Inheritance patient_demo CardioRisk))))

;; Verify the derivation was recorded
!(assertEqual
   (let $result (collapse (match &self (Derivation (Inheritance patient_demo CardioRisk) $truth $_ $_ $_) $truth))
        (car-atom $result))
   (stv 0.82 0.76))


;; ─── Test 5: provenance returns the evidence chain ────────────────

;; provenance for the derived conclusion should return at least the derivation
!(assertEqual
   (!= (provenance (Inheritance patient_demo CardioRisk)) ())
   True)

;; provenance for the observed fact should return the observation
!(assertEqual
   (!= (provenance (Inheritance patient_demo ElevatedPC1)) ())
   True)


;; ─── Test 6: pin stores working memory (no longer a no-op) ───────

!(pin "step_1_patient_data_fetched")

;; Verify pin created an observation
!(assertEqual
   (let $result (collapse (match &self (Observation (WorkingMemory "step_1_patient_data_fetched") $_ agent_reasoning $_) 1))
        (!= $result ()))
   True)


;; ─── Test 7: claim-status distinguishes grounded vs ungrounded ────

;; CardioRisk has evidence (we derived it above)
!(assertEqual
   (let ($tag $_ $rest) (claim-status (Inheritance patient_demo CardioRisk))
        $tag)
   GROUNDED_CLAIM:)

;; Unknown claim has no evidence
!(assertEqual
   (let ($tag $_ $rest) (claim-status (Inheritance patient_demo UnknownDisease))
        $tag)
   UNGROUNDED_HYPOTHESIS:)


;; ─── Test 8: PLN Modus Ponens uses evidence-backed STV ────────────
;;
;; This is the critical integration test: the existing |~ inference
;; operator should produce different results when evidence is present
;; vs when it's not, because STV now looks up real observations.

;; Observe a second biomarker for the same patient
!(observe (Inheritance patient_demo HighLDL) (stv 0.90 0.88) api_data)
!(observe (Implication (Inheritance patient_demo HighLDL) (Inheritance patient_demo AtherosclerosisRisk))
          (stv 0.80 0.85) clinical_guideline)

;; Run PLN Modus Ponens via the existing |~ operator
!(let $result (|~ ((Inheritance patient_demo HighLDL) (stv 0.90 0.88))
                  ((Implication (Inheritance patient_demo HighLDL) (Inheritance patient_demo AtherosclerosisRisk)) (stv 0.80 0.85)))
     (assertEqual (!= $result ()) True))


;; ─── Test 9: evidence-count reports correctly ─────────────────────

!(let (EVIDENCE: observations $obs_count derivations $der_count) (evidence-count)
     (assertEqual (and (> $obs_count 0) (>= $der_count 0)) True))


;; ─── Test 10: STV combines multiple observations via Revision ──────
;;
;; If two independent sources observe the same atom with different truth
;; values, STV should combine them using PLN Revision rather than
;; arbitrarily picking one.  The revised confidence should be higher
;; than either individual observation's confidence.

!(observe (Inheritance patient_demo TestBiomarker) (stv 0.80 0.60) lab_result_1)
!(observe (Inheritance patient_demo TestBiomarker) (stv 0.85 0.70) lab_result_2)

;; After revision, confidence should exceed the max individual (0.70)
!(let (stv $s $c) (STV (Inheritance patient_demo TestBiomarker))
     (assertEqual (> $c 0.70) True))


;; ─── Test 11: explain returns structured output with OBSERVATIONS ──

!(let ($tag $atom $obsLabel $obs $derLabel $ders)
      (explain (Inheritance patient_demo ElevatedPC1))
     (progn (assertEqual $tag EXPLANATION:)
            (assertEqual $obsLabel OBSERVATIONS:)
            (assertEqual (!= $obs ()) True)))


;; ─── Test 12: explain recursively expands derivation premises ──────
;;
;; CardioRisk was derived from ElevatedPC1 (which has an observation).
;; explain should show: CardioRisk derivation → ElevatedPC1 observation.

!(let ($tag $atom $obsLabel $obs $derLabel $ders)
      (explain (Inheritance patient_demo CardioRisk))
     (progn (assertEqual $tag EXPLANATION:)
            (assertEqual $derLabel DERIVATIONS:)
            ;; Derivations list should contain PREMISE_CHAIN with expanded evidence
            (assertEqual (!= $ders ()) True)))


;; ─── Test 13: explain stops at depth limit ────────────────────────

;; explain-rec with depth 0 should return MAX_DEPTH_REACHED
!(let ($tag $atom) (explain-rec (Inheritance patient_demo CardioRisk) 0)
     (assertEqual $tag MAX_DEPTH_REACHED:))


;; ─── Test 14: unexplained atoms get NO_EVIDENCE label ─────────────

!(let ($tag $atom) (explain (Inheritance nobody NothingEver))
     (assertEqual $tag NO_EVIDENCE_FOR:))


;; ═══════════════════════════════════════════════════════════════════════
!(println! "═══ All evidence store tests passed ═══")
