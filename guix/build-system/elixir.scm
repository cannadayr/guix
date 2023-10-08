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
  #:use-module (guix packages)
  #:use-module (guix derivations)
  #:use-module (guix search-paths)
  #:use-module (guix build-system)
  #:use-module (guix build-system gnu)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-26)
  ;; #:use-module ((guix build-system rebar)
  ;;               #:select ((hexpm-uri . hexpm-uri)))
  #:export (%elixir-build-system-modules
            hexpm-uri
            elixir-build
            elixir-build-system))

;;
;; Standard build procedure for Elixir packages using Mix.
;;

(define %hexpm-repo-url
  (make-parameter "https://repo.hex.pm"))

(define hexpm-package-url
  (string-append (%hexpm-repo-url) "/tarballs/"))

(define (hexpm-uri name version)
  "Return a URI string for the package hosted at hex.pm corresponding to NAME
and VERSION."
  (string-append hexpm-package-url name "-" version ".tar"))


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
  "Return a bag for NAME."
  (define private-keywords
    '(#:source #:target #:rebar #:inputs #:native-inputs))

  (and (not target)                               ;XXX: no cross-compilation
       (bag
         (name name)
         (system system)
         (host-inputs `(,@(if source
                              `(("source" ,source))
                              '())
                        ,@inputs
                        ;; Keep the standard inputs of 'gnu-build-system'.
                        ,@(standard-packages)))
         (build-inputs `(("elixir" ,elixir)
                         ,@native-inputs))
         (outputs outputs)
         (build elixir-build)
         (arguments (strip-keyword-arguments private-keywords arguments)))))

(define* (elixir-build store name inputs
                       #:key
                       (tests? #t)
                       (test-target "test")
                       (configure-flags ''())
                       (make-flags ''())
                       (build-target "compile")
                       (build-environment "prod")
                       ;; TODO: pkg-name
                       (phases '(@ (guix build elixir-build-system)
                                   %standard-phases))
                       (outputs '("out"))
                       (search-paths '())
                       (system (%current-system))
                       (guile #f)
                       (imported-modules %elixir-build-system-modules)
                       (modules '((guix build elixir-build-system)
                                  (guix build utils))))
  "Build SOURCE with INPUTS."
  (define builder
    `(begin
       (use-modules ,@modules)
       (elixir-build #:name ,name
                     #:source ,(match (assoc-ref inputs "source")
                                      (((? derivation? source))
                                       (derivation->output-path source))
                                      ((source)
                                       source)
                                      (source
                                       source))
                     #:make-flags ,make-flags
                     #:configure-flags ,configure-flags
                     #:system ,system
                     #:tests? ,tests?
                     #:test-target ,test-target
                     #:build-target ,build-target
                     #:build-environment ,build-environment
                     #:phases ,phases
                     #:outputs %outputs
                     #:search-paths ',(map search-path-specification->sexp
                                           search-paths)
                     #:inputs %build-inputs)))

  (define guile-for-build
    (match guile
      ((? package?)
       (package-derivation store guile system #:graft? #f))
      (#f                               ; the default
       (let* ((distro (resolve-interface '(gnu packages commencement)))
              (guile  (module-ref distro 'guile-final)))
         (package-derivation store guile system #:graft? #f)))))

  (build-expression->derivation store name builder
                                #:inputs inputs
                                #:system system
                                #:modules imported-modules
                                #:outputs outputs
                                #:guile-for-build guile-for-build))

(define elixir-build-system
  (build-system
    (name 'elixir)
    (description "The standard build system for Elixir")
    (lower lower)))
