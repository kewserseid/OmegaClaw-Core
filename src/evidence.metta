;; Evidence Store: grounded reasoning with provenance

;; Record a grounded fact.
(= (observe $atom $truth $source)
   (let $time (get_time_as_string)
        (progn (add-atom &self (Observation $atom $truth $source $time))
               (OBSERVED: $atom $truth FROM: $source AT: $time))))

;; Record a PLN-derived conclusion.
(= (derive $conclusion $truth $rule $premises)
   (let $time (get_time_as_string)
        (progn (add-atom &self (Derivation $conclusion $truth $rule $premises $time))
               (DERIVED: $conclusion $truth VIA: $rule AT: $time))))

;; Override STV to use real evidence, combined via PLN Revision.
(= (STV $X)
   (let $obs (collapse (match &self (Observation $X $truth $_ $_) $truth))
        (if (!= $obs ())
            (fold-revision $obs)
            (let $der (collapse (match &self (Derivation $X $truth $_ $_ $_) $truth))
                 (if (!= $der ())
                     (fold-revision $der)
                     (stv (/ 1.0 10.0) 0.9))))))

;; Fold truth values using PLN Revision.
(= (fold-revision $truths)
   (if (== (length $truths) 1)
       (car-atom $truths)
       (Truth__Revision (car-atom $truths)
                        (fold-revision (cdr-atom $truths)))))

;; Return immediate evidence supporting an atom.
(= (provenance $atom)
   (collapse (superpose
     ((match &self (Observation $atom $truth $source $time)
                   (OBSERVATION: $atom TRUTH: $truth SOURCE: $source TIME: $time))
      (match &self (Derivation $atom $truth $rule $premises $time)
                   (DERIVATION: $atom TRUTH: $truth RULE: $rule FROM: $premises TIME: $time))))))

;; Recursive, depth-limited provenance chain.
(= (explain $atom) (explain-rec $atom 4))

(= (explain-rec $atom 0) (MAX_DEPTH_REACHED: $atom))

(= (explain-rec $atom $depth)
   (let* (($obs (collapse (match &self (Observation $atom $truth $source $time)
                                  (OBSERVATION: $atom TRUTH: $truth SOURCE: $source TIME: $time))))
          ($ders (collapse (match &self (Derivation $atom $truth $rule $premises $time)
                                  (DERIVATION: $atom TRUTH: $truth RULE: $rule
                                    PREMISE_CHAIN: (expand-premises $premises (- $depth 1))
                                    TIME: $time)))))
         (if (and (== $obs ()) (== $ders ()))
             (NO_EVIDENCE_FOR: $atom)
             (EXPLANATION: $atom OBSERVATIONS: $obs DERIVATIONS: $ders))))

;; Expand premises recursively.
(= (expand-premises $premises $depth)
   (collapse (let $p (superpose $premises)
                  (explain-rec $p $depth))))

;; Store working-memory state.
(= (pin $x)
   (let $time (get_time_as_string)
        (progn (add-atom &self (Observation (WorkingMemory $x) (stv 1.0 0.9) agent_reasoning $time))
               PIN-SUCCESS)))

;; List all evidence in the store.
(= (all-evidence)
   (collapse (superpose
     ((match &self (Observation $a $t $s $time) (OBS: $a $t $s $time))
      (match &self (Derivation $a $t $r $p $time) (DER: $a $t $r $p $time))))))

;; Count observations and derivations.
(= (evidence-count)
   (let* (($obs (collapse (match &self (Observation $_ $_ $_ $_) 1)))
          ($der (collapse (match &self (Derivation $_ $_ $_ $_ $_) 1))))
         (EVIDENCE: observations (length $obs) derivations (length $der))))

;; Check whether a specific atom has any grounded evidence.
(= (has-evidence $atom)
   (let $all (collapse (superpose
     ((match &self (Observation $atom $_ $_ $_) True)
      (match &self (Derivation $atom $_ $_ $_ $_) True))))
        (!= $all ())))

;; Label a conclusion: grounded or hypothesis.
(= (claim-status $atom)
   (if (has-evidence $atom)
       (GROUNDED_CLAIM: $atom EVIDENCE: (provenance $atom))
       (UNGROUNDED_HYPOTHESIS: $atom NOTE: no_symbolic_evidence_found)))
