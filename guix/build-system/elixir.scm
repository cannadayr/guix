;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2016 Ricardo Wurmus <rekado@elephly.net>
;;; Copyright © 2020 Hartmut Goebel <h.goebel@crazy-compilers.com>
;;;
;;; This file is part of GNU Guix.
;;;
;;; GNU Guix is free software; you can redistribute it and/or modify it
;;; under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 3 of the License, or (at
;;; your option) any later version.
;;;
;;; GNU Guix is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with GNU Guix.  If not, see <http://www.gnu.org/licenses/>.

(define-module (guix build-system elixir)
  #:use-module (guix store)
  #:use-module (guix utils)
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:use-module (guix monads)
  #:use-module (guix search-paths)
  #:use-module (guix build-system)
  #:use-module (guix build-system gnu)
  #:use-module ((guix build-system rebar)
                #:select ((hexpm-uri . hexpm-uri)))
  #:re-export (hexpm-uri)
  #:export (%elixir-build-system-modules
            elixir-build
            elixir-build-system))

;;
;; Standard build procedure for Elixir packages using Mix.
;;

(define %elixir-build-system-modules
  ;; Build-side modules imported by default.
  `((guix build elixir-build-system)
    ,@%gnu-build-system-modules))

(define (default-elixir)
  "Return the default Elixir package."
  ;; Lazily resolve the binding to avoid a circular dependency.
  (let ((elixir-mod (resolve-interface '(gnu packages elixir))))
    (module-ref elixir-mod 'elixir)))

(define* (lower name
                #:key source inputs native-inputs outputs system target
                (elixir (default-elixir))
                #:allow-other-keys
                #:rest arguments)
  "Return a bag for NAME from the given arguments."
  (define private-keywords
    '(#:source #:target #:mix #:inputs #:native-inputs))

  (and (not target)                               ;XXX: no cross-compilation
       (bag
         (name name)
         (system system)
         (host-inputs `(,@(if source
                              `(("source" ,source))
                              '())
                        ,@inputs))
         (build-inputs `(("elixir" ,elixir)
                         ,@native-inputs
                         ;; Keep the standard inputs of 'gnu-build-system'.
                         ,@(standard-packages)))
         (outputs outputs)
         (build elixir-build)
         (arguments (strip-keyword-arguments private-keywords arguments)))))

(define* (elixir-build name inputs
                       #:key
                       guile source
                       (mix-flags ''())
                       (tests? #t)
                       (test-target "test")
                       ;; (make-flags ''())
                       (build-target "compile")
                       (build-environment "prod") ;; install-profile ??
                       ;; TODO: install-name  ; default: based on guix package name
                       (phases '(@ (guix build elixir-build-system)
                                   %standard-phases))
                       (outputs '("out"))
                       (search-paths '())
                       (native-search-paths '())
                       (system (%current-system))
                       (imported-modules %elixir-build-system-modules)
                       (modules '((guix build elixir-build-system)
                                  (guix build utils))))
  "Build SOURCE with INPUTS."

  (define builder
    (with-imported-modules imported-modules
      #~(begin
          (use-modules #$@(sexp->gexp modules))

          #$(with-build-variables inputs outputs
              #~(elixir-build #:source #+source
                      #:system #$system
                      #:name #$name
                      #:mix-flags #$mix-flags
                      #:tests? #$tests?
                      #:test-target #$test-target
                      #:build-target #$build-target
                      #:build-environment #$build-environment
                     ;; TODO: #:install-name #$install-name
                      #:phases #$(if (pair? phases)
                                     (sexp->gexp phases)
                                     phases)
                      #:outputs %outputs
                      #:search-paths '#$(sexp->gexp
                                         (map search-path-specification->sexp
                                              search-paths))
                      #:inputs %build-inputs)))))

  (mlet %store-monad ((guile (package->derivation (or guile (default-guile))
                                                  system #:graft? #f)))
    ;; Note: Always pass #:graft? #f.  Without it, ALLOWED-REFERENCES &
    ;; co. would be interpreted as referring to grafted packages.
    (gexp->derivation name builder
                      #:system system
                      #:target #f
                      #:graft? #f
                      #:guile-for-build guile)))

(define elixir-build-system
  (build-system
    (name 'elixir)
    (description "The standard build system for Elixir")
    (lower lower)))
