;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2016 Leo Famulari <leo@famulari.name>
;;; Copyright © 2016, 2017 Pjotr Prins <pjotr.guix@thebird.nl>
;;; Copyright © 2016 Ricardo Wurmus <rekado@elephly.net>
;;; Copyright © 2017 nee <nee.git@cock.li>
;;; Copyright © 2018, 2019, 2021 Tobias Geerinckx-Rice <me@tobias.gr>
;;; Copyright © 2018 Nikita <nikita@n0.is>
;;; Copyright © 2020, 2021 Hartmut Goebel <h.goebel@crazy-compilers.com>
;;; Copyright © 2021 Oskar Köök <oskar@maatriks.ee>
;;; Copyright © 2021 Cees de Groot <cg@evrl.com>
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

(define-module (gnu packages elixir)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix build-system gnu)
  #:use-module (guix build-system elixir)
  #:use-module (guix gexp)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (guix packages)
  #:use-module (gnu packages)
  #:use-module (gnu packages erlang)
  #:use-module (gnu packages version-control))

(define-public elixir
  (package
    (name "elixir")
    (version "1.14.0")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/elixir-lang/elixir")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "16rc4qaykddda6ax5f8zw70yhapgwraqbgx5gp3f40dvfax3d51l"))
       (patches (search-patches "elixir-path-length.patch"))))
    (build-system gnu-build-system)
    (arguments
     (list
      #:test-target "test"
      #:parallel-tests? #f ;see <https://debbugs.gnu.org/cgi/bugreport.cgi?bug=32171#23>
      #:make-flags #~(list (string-append "PREFIX=" #$output))
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'unpack 'make-git-checkout-writable
            (lambda _
              (for-each make-file-writable (find-files "."))))
          (add-after 'make-git-checkout-writable 'replace-paths
            (lambda* (#:key inputs #:allow-other-keys)
              ;; Note: references end up obfuscated in binary BEAM files where
              ;; they may be invisible to the GC and graft code:
              ;; <https://issues.guix.gnu.org/54304#11>.
              (substitute* '("lib/mix/lib/mix/release.ex"
                             "lib/mix/lib/mix/tasks/release.init.ex")
                (("#!/bin/sh")
                 (string-append "#!" (search-input-file inputs "/bin/sh"))))
              (substitute* "bin/elixir"
                (("ERTS_BIN=\n")
                 (string-append
                  "ERTS_BIN="
                  ;; Elixir Releases will prepend to ERTS_BIN the path of
                  ;; a copy of erl.  We detect if a release is being generated
                  ;; by checking the initial ERTS_BIN value: if it's empty, we
                  ;; are not in release mode and can point to the actual erl
                  ;; binary in Guix store.
                  "\nif [ -z \"$ERTS_BIN\" ]; then ERTS_BIN="
                  (string-drop-right (search-input-file inputs "/bin/erl") 3)
                  "; fi\n")))
              (substitute* "bin/mix"
                (("#!/usr/bin/env elixir")
                 (string-append "#!" #$output "/bin/elixir")))))
          (add-before 'build 'make-current
            ;; The Elixir compiler checks whether or not to compile files by
            ;; inspecting their timestamps.  When the timestamp is equal to the
            ;; epoch no compilation will be performed.  Some tests fail when
            ;; files are older than Jan 1, 2000.
            (lambda _
              (for-each (lambda (file)
                          (let ((recent 1400000000))
                            (utime file recent recent 0 0)))
                        (find-files "." ".*"))))
          (add-before 'check 'set-home
            (lambda* (#:key inputs #:allow-other-keys)
              ;; Some tests require access to a home directory.
              (setenv "HOME" "/tmp")))
          (delete 'configure))))
    (inputs
     (list erlang git))
    (home-page "https://elixir-lang.org/")
    (synopsis "Elixir programming language")
    (description "Elixir is a dynamic, functional language used to build
scalable and maintainable applications.  Elixir leverages the Erlang VM, known
for running low-latency, distributed and fault-tolerant systems, while also
being successfully used in web development and the embedded software domain.")
    (license license:asl2.0)))

(define-public elixir-artificery
  (package
    (name "elixir-artificery")
    (version "0.4.3")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "artificery" version))
              (sha256
               (base32
                "0105zjghn01zncvwza1bkih0apkz7vxbxgbsjd78h80flcrm7s8j"))))
    (build-system elixir-build-system)
    (inputs (list erlang-hex-core))
    (home-page "https://github.com/bitwalker/artificery")
    (synopsis "Toolkit for terminal user interfaces in Elixir")
    (description "This package provides a toolkit for terminal user interfaces
in Elixir.")
    (license license:asl2.0)))

(define-public elixir-distillery
  (package
    (name "elixir-distillery")
    (version "2.1.1")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "distillery" version))
              (sha256
               (base32
                "1599wan14amzzkw93a9ikk6gql934frva0yrv0qg39k1065h1ixv"))))
    (build-system elixir-build-system)
    (inputs (list elixir-artificery))
    (home-page "https://github.com/bitwalker/distillery")
    (synopsis "Build releases of Mix projects")
    (description
     "Distillery is a tool for packaging Elixir applications for
deployment using OTP releases.  In a nutshell, Distillery produces an artifact,
a tarball, which contains your application and everything needed to run it.")
    (license license:expat)))

(define-public elixir-earmark-parser
  (package
    (name "elixir-earmark-parser")
    (version "1.4.26")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "earmark_parser" version))
              (sha256
               (base32
                "1g5ajj6l4j1nnkd6vcnhp8vk6kzn04f62xh68z2m434aky4n1m28"))))
    (build-system elixir-build-system)
    (home-page "https://github.com/RobertDober/earmark_parser")
    (synopsis "Pure Elixir Markdown Parser")
    (description
     "Earmark AST the parser and AST Generator for Dave Thomas'
Earmark.  The parser generates an Abstract Syntax Tree from Markdown.

The original Earmark will still provide the HTML Transformation and
the CLI, however its Scanner, Parser and AST Renderer have been
extracted into this library.")
    (license license:asl2.0)))

(define-public elixir-earmark
  (package
    (name "elixir-earmark")
    (version "1.4.26")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "earmark" version))
              (sha256
               (base32
                "1ibqz982fvzir4fwnbnwqa0db73cy1chjgzk59ly1v3bnn11h8z1"))))
    (build-system elixir-build-system)
    (inputs (list elixir-earmark-parser))
    (home-page "https://github.com/pragdave/earmark")
    (synopsis "Pure Elixir Markdown converter")
    (description
     "This package provides a pure-Elixir Markdown converter.  It
is intended to be used as a library (just call Earmark.as_html), but can also
be used as a command-line tool (run mix escript.build first).  The Output
generation is pluggable.")
    (license license:asl2.0)))

(define-public elixir-eqc-ex
  (package
    (name "elixir-eqc-ex")
    (version "1.4.2")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "eqc_ex" version))
              (sha256
               (base32
                "0f0gsp56shs09qdrqhjs7kkinzxh6qhk7qzpglwaak32a61yciv5"))))
    (build-system elixir-build-system)
    (home-page "https://github.com/Quviq/eqc_ex")
    (synopsis "Wrappers to facilitate using Quviq QuickCheck with Elixir")
    (description "This package defines wrappers for using Quviq QuickCheck
with Elixir.")
    (license license:bsd-3)))

(define-public elixir-makeup
  (package
    (name "elixir-makeup")
    (version "1.1.0")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "makeup" version))
              (sha256
               (base32
                "19jpprryixi452jwhws3bbks6ki3wni9kgzah3srg22a3x8fsi8a"))))
    (build-system elixir-build-system)
    (inputs (list elixir-nimble-parsec))
    (home-page "https://github.com/elixir-makeup/makeup")
    (synopsis "Syntax highlighter for source code in the style of Pygments")
    (description "Syntax highlighter for source code in the style of
Pygments.")
    (license license:bsd-2)))

(define-public elixir-makeup-elixir
  (package
    (name "elixir-makeup-elixir")
    (version "0.16.0")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "makeup_elixir" version))
              (sha256
               (base32
                "1rrqydcq2bshs577z7jbgdnrlg7cpnzc8n48kap4c2ln2gfcpci8"))))
    (build-system elixir-build-system)
    (inputs (list elixir-makeup elixir-nimble-parsec))
    (home-page "https://github.com/elixir-makeup/makeup_elixir")
    (synopsis "Elixir lexer for the Makeup syntax highlighter")
    (description "This package provides an Elixir lexer for the Makeup syntax
highlighter.")
    (license license:bsd-2)))

(define-public elixir-makeup-erlang
  (package
    (name "elixir-makeup-erlang")
    (version "0.1.1")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "makeup_erlang" version))
              (sha256
               (base32
                "00dnn8g8sr8clgyhnihqjw6wlikml6499ff5va8q8hsi53ng7v20"))))
    (build-system elixir-build-system)
    (inputs (list elixir-makeup))
    (home-page "https://github.com/elixir-makeup/makeup_erlang")
    (synopsis "Erlang lexer for the Makeup syntax highlighter")
    (description "This package provides a makeup lexer for the Erlang
language.")
    (license license:bsd-2)))  ;; Unclear which "BSD" license

(define-public elixir-nimble-parsec
  (package
    (name "elixir-nimble-parsec")
    (version "1.1.0")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "nimble_parsec" version))
              (sha256
               (base32
                "063ibzqf7jijwqbj211sr747cmncnb4lryqjfa577yrcv44hc3f1"))))
    (build-system elixir-build-system)
    (home-page "https://github.com/dashbitco/nimble_parsec")
    (synopsis "Simple and fast library for text-based parser combinators")
    (description "This package provides a simple and fast library for
text-based parser combinators.")
    (license license:asl2.0)))

(define-public elixir-html-entities
  (package
    (name "elixir-html-entities")
    (version "0.5.2")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "html_entities" version))
              (sha256
               (base32
                "1k7xyj0q38ms3n5hbn782pa6w1vgd6biwlxr4db6319l828a6fy5"))))
    (build-system elixir-build-system)
    (home-page "https://github.com/martinsvalin/html_entities")
    (synopsis "Decode and encode HTML entities in a string")
    (description "This package provides a Elixir module to decode and encode
HTML entities in a string.")
    (license license:expat)))

(define-public elixir-floki
  (package
    (name "elixir-floki")
    (version "0.32.1")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "floki" version))
              (sha256
               (base32
                "18w1qv9syz464914d61q3imryqgwxqbc0g0ygczlly2a7rqirffl"))))
    (build-system elixir-build-system)
    (inputs (list elixir-html-entities))
    (home-page "https://github.com/philss/floki")
    (synopsis "Simple HTML parser that enables search for nodes using CSS
selectors")
    (description "@code{Floki} is a simple HTML parser that enables search for
nodes using CSS selectors.")
    (license license:expat)))

(define-public elixir-ex-doc
  (package
    (name "elixir-ex-doc")
    (version "0.28.4")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "ex_doc" version))
              (sha256
               (base32
                "1vgqqf5cf0cw18aw593ll9qk9bsqm6hvvf6xr24iv49lvl1x11dz"))))
    (build-system elixir-build-system)
    (inputs (list elixir-earmark-parser elixir-makeup-elixir
                  elixir-makeup-erlang))
    (home-page "https://github.com/elixir-lang/ex_doc")
    (synopsis "Documentation generation tool for Elixir")
    (description "This package provides a documentation generation tool for
Elixir.")

(define-public elixir-extractly
  (package
    (name "elixir-extractly")
    (version "0.5.3")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "extractly" version))
              (sha256
               (base32
                "00smi3mbdsyjfyb8lwj2bdz3pjzy0dpqdf2vwwvpjxpvbwl7m3w5"))))
    (build-system elixir-build-system)
    (home-page "https://github.com/robertdober/extractly")
    (synopsis "Easy access to information inside the templates rendered by
@code{mix xtra}")
    (description
     "This package provides easy access to information inside the
templates rendered by @code{mix xtra}.  The Extractly module gives easy access
to Elixir metainformation of the application using the extractly package,
notably, module and function documentation.")
    (license license:asl2.0)))
