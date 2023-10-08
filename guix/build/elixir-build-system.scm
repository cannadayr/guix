;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2016, 2018 Ricardo Wurmus <rekado@elephly.net>
;;; Copyright © 2019 Björn Höfling <bjoern.hoefling@bjoernhoefling.de>
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

(define-module (guix build elixir-build-system)
  #:use-module ((guix build gnu-build-system) #:prefix gnu:)
  ;;#:use-module (guix build syscalls)
  #:use-module ((guix build utils) #:hide (delete))
  #:use-module (ice-9 match)
  #:use-module (ice-9 ftw)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-26)
  #:export (%standard-phases
            elixir-build))

;;
;; Builder-side code of the standard build procedure for Elixir packages using
;; Mix.
;;
;; TODO: Think about whether bindir ("ebin"), libdir ("priv") and includedir
;; "(include") need to be configurable

(define %elixir-libdir "/lib/elixir/lib")

(define* (elixir-depends #:key inputs #:allow-other-keys)
  (define input-directories
    (match inputs
      (((_ . dir) ...)
       dir)))
  (mkdir-p "_checkouts")

  (for-each
   (lambda (input-dir)
     (let ((elibdir (string-append input-dir %elixir-libdir)))
       (when (directory-exists? elibdir)
         (for-each
          (lambda (dirname)
            (symlink (string-append elibdir "/" dirname)
                     (string-append "_checkouts/" dirname)))
          (list-directories elibdir)))))
   input-directories)
  #t)

(define* (unpack #:key source #:allow-other-keys)
  "Unpack SOURCE in the working directory, and change directory within the
source.  When SOURCE is a directory, copy it in a sub-directory of the current
working directory."
  ;; archives from hexpm typicalls do not contain a directory level
  ;; TODO: Check if archive contains a directory level
  (mkdir "source")
  (chdir "source")
  (if (file-is-directory? source)
      (begin
        ;; Preserve timestamps (set to the Epoch) on the copied tree so that
        ;; things work deterministically.
        (copy-recursively source "."
                          #:keep-mtime? #t))
      (begin
        (if (string-suffix? ".zip" source)
            (invoke "unzip" source)
            (invoke "tar" "xvf" source))))
  #t)

(define* (build #:key (build-target "compile") (build-environment "prod")
                #:allow-other-keys)
  (setenv "MIX_ENV" build-environment)
  (apply invoke `("mix" ,build-target)))

(define* (check #:key target (tests? (not target))
                (test-target "test") (test-environment "test")
                #:allow-other-keys)
  (if tests?
      (begin
        (setenv "MIX_ENV" test-environment)
        (invoke "mix" test-target))
      (format #t "test suite not run~%"))
  #t)

(define (elixir-package? name)
  "Check if NAME correspond to the name of an Elixir package."
  (string-prefix? "elixir-" name))

(define (package-name-version->elixir-name name+ver)
  "Convert the Guix package NAME-VER to the corresponding Elixir name-version
format.  Essentially drop the prefix used in Guix and replace dashes by
underscores."
  (let* ((name- (package-name->name+version name+ver)))
    (string-join
     (string-split
      (if (elixir-package? name-)  ; checks for "elixir-" prefix
          (string-drop name- (string-length "elixir-"))
          name-)
      #\-)
     "_")))

(define (list-directories directory)
  "Return file names of the sub-directory of DIRECTORY."
  (scandir directory
           (lambda (file)
             (and (not (member file '("." "..")))
                  (file-is-directory? (string-append directory "/" file))))))

(define* (install #:key name outputs
                  (pkg-name (package-name-version->elixir-name name))
                  #:allow-other-keys)
  (let* ((out (assoc-ref outputs "out"))
         (build-dir "_build/prod/lib")
         (pkg-dir (string-append out %elixir-libdir "/" pkg-name)))
    (for-each
     (lambda (pkg)
       (for-each
        (lambda (dirname)
          (let ((src-dir (string-append build-dir "/" pkg "/" dirname))
                (dst-dir (string-append pkg-dir "/" dirname)))
            (when (file-exists? src-dir)
              (copy-recursively src-dir dst-dir #:follow-symlinks? #t))
            (false-if-exception
             (delete-file (string-append dst-dir "/.gitignore")))))
        '("ebin" "include" "priv")))
     (list-directories build-dir))
    (false-if-exception
     (delete-file (string-append pkg-dir "/priv/Run-eunit-loop.expect")))
    #t))

(define %standard-phases
  (modify-phases gnu:%standard-phases
    (replace 'unpack unpack)
    (delete 'bootstrap)
    (delete 'configure)
    (add-before 'build 'elixir-depends elixir-depends)
    (replace 'build build)
    (replace 'check check)
    (replace 'install install)))

(define* (elixir-build #:key inputs (phases %standard-phases)
                       #:allow-other-keys #:rest args)
  "Build the given Elixir package, applying all of PHASES in order."
  (apply gnu:gnu-build #:inputs inputs #:phases phases args))
