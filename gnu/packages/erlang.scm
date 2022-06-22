;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2016 Steve Sprang <scs@stevesprang.com>
;;; Copyright © 2016, 2017 Leo Famulari <leo@famulari.name>
;;; Copyright © 2016, 2017 Pjotr Prins <pjotr.guix@thebird.nl>
;;; Copyright © 2018 Tobias Geerinckx-Rice <me@tobias.gr>
;;; Copyright © 2018 Nikita <nikita@n0.is>
;;; Copyright © 2020-2022 Hartmut Goebel <h.goebel@crazy-compilers.com>
;;; Copyright © 2021 Oskar Köök <oskar@maatriks.ee>
;;; Copyright © 2021 Cees de Groot <cg@evrl.com>
;;; Copyright © 2022 jgart <jgart@dismail.de>
;;; Copyright © 2023 wrobell <wrobell@riseup.net>
;;; Copyright © 2023 Tim Johann <t1m@phrogstar.de>
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

(define-module (gnu packages erlang)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix gexp)
  #:use-module (guix build-system gnu)
  #:use-module (guix build-system emacs)
  #:use-module (guix build-system rebar)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (guix packages)
  #:use-module (guix utils)
  #:use-module (gnu packages)
  #:use-module (gnu packages fontutils)
  #:use-module (gnu packages gd)
  #:use-module (gnu packages gl)
  #:use-module (gnu packages image)
  #:use-module (gnu packages ncurses)
  #:use-module (gnu packages perl)
  #:use-module (gnu packages serialization)
  #:use-module (gnu packages version-control)
  #:use-module (gnu packages tls)
  #:use-module (gnu packages wxwidgets))

(define-public erlang
  (package
    (name "erlang")
    (version "25.3.2")
    (source (origin
              (method git-fetch)
              ;; The tarball from http://erlang.org/download contains many
              ;; pre-compiled files, so we use this snapshot of the source
              ;; repository.
              (uri (git-reference
                    (url "https://github.com/erlang/otp")
                    (commit (string-append "OTP-" version))))
              (file-name (git-file-name name version))
              (sha256
               (base32
                "092lym5a181gz89nscw7kqhw1wa6qvgcpkj80q4i9p79mxmsr1nj"))
              (patches (search-patches "erlang-man-path.patch"))))
    (build-system gnu-build-system)
    (native-inputs
     `(("perl" ,perl)

       ;; Erlang's documentation is distributed in a separate tarball.
       ("erlang-manpages"
        ,(origin
           (method url-fetch)
           (uri (string-append "http://erlang.org/download/otp_doc_man_"
                               (version-major+minor version) ".tar.gz"))
           (sha256
            (base32
             "0vnpds5q17xc4jjj3sbsllpx68wyhgvx70714vkzyd68rbjmhmk7"))))))
    (inputs
     (list ncurses openssl wxwidgets))
    (propagated-inputs
     (list fontconfig glu mesa))
    (arguments
     `(#:test-target "release_tests"
       #:configure-flags
       (list "--disable-saved-compile-time"
             "--enable-dynamic-ssl-lib"
             "--enable-native-libs"
             "--enable-shared-zlib"
             "--enable-smp-support"
             "--enable-threads"
             "--enable-wx"
             (string-append "--with-ssl=" (assoc-ref %build-inputs "openssl")))
       #:modules ((srfi srfi-19)        ; make-time, et cetera.
                  (guix build utils)
                  (guix build gnu-build-system))
       #:phases
       (modify-phases %standard-phases
         (delete 'bootstrap)
         ;; The are several code fragments that embed timestamps into the
         ;; output. Here, we alter those fragments to use the value of
         ;; SOURCE_DATE_EPOCH instead.
         (add-after 'unpack 'remove-timestamps
           (lambda _
             (let ((source-date-epoch
                    (time-utc->date
                     (make-time time-utc 0 (string->number
                                            (getenv "SOURCE_DATE_EPOCH"))))))
               (substitute* "lib/reltool/src/reltool_target.erl"
                 (("Date = date\\(\\),")
                  (string-append "Date = "
                                 (date->string source-date-epoch
                                               "'{~Y,~m,~d}',"))))
               (substitute* "lib/reltool/src/reltool_target.erl"
                 (("Time = time\\(\\),")
                  (string-append "Time = "
                                 (date->string source-date-epoch
                                               "'{~H,~M,~S}',"))))
               (substitute* '("lib/reltool/src/reltool_target.erl"
                              "lib/sasl/src/systools_make.erl")
                 (("date\\(\\), time\\(\\),")
                  (date->string source-date-epoch
                                "{~Y,~m,~d}, {~H,~M,~S},")))
               (substitute* "lib/dialyzer/test/small_SUITE_data/src/gs_make.erl"
                 (("tuple_to_list\\(date\\(\\)\\),tuple_to_list\\(time\\(\\)\\)")
                  (date->string
                   source-date-epoch
                   "tuple_to_list({~Y,~m,~d}), tuple_to_list({~H,~M,~S})")))
               (substitute* "lib/snmp/src/compile/snmpc_mib_to_hrl.erl"
                 (("\\{Y,Mo,D\\} = date\\(\\),")
                  (date->string source-date-epoch
                                "{Y,Mo,D} = {~Y,~m,~d},")))
               (substitute* "lib/snmp/src/compile/snmpc_mib_to_hrl.erl"
                 (("\\{H,Mi,S\\} = time\\(\\),")
                  (date->string source-date-epoch
                                "{H,Mi,S} = {~H,~M,~S},"))))))
         (add-after 'unpack 'patch-/bin/sh
           (lambda* (#:key inputs #:allow-other-keys)
             (let ((sh (search-input-file inputs "/bin/sh")))
               (substitute* "erts/etc/unix/run_erl.c"
                 (("sh = \"/bin/sh\";")
                  (string-append "sh = \"" sh "\";")))
               (substitute* "erts/emulator/sys/unix/sys_drivers.c"
                 (("SHELL \"/bin/sh\"")
                  (string-append "SHELL \"" sh "\"")))
               (substitute* "erts/emulator/sys/unix/erl_child_setup.c"
                 (("SHELL \"/bin/sh\"")
                  (string-append "SHELL \"" sh "\"")))
               (substitute* "lib/kernel/src/os.erl"
                 (("/bin/sh") sh)))))
         (add-after 'patch-source-shebangs 'patch-source-env
           (lambda _
             (let ((escripts
                    (append
                        (find-files "." "\\.escript")
                        (find-files "lib/stdlib/test/escript_SUITE_data/")
                      '("erts/lib_src/utils/make_atomics_api"
                        "erts/preloaded/src/add_abstract_code"
                        "lib/diameter/bin/diameterc"
                        "lib/reltool/examples/display_args"
                        "lib/reltool/examples/mnesia_core_dump_viewer"
                        "lib/snmp/src/compile/snmpc.src"
                        "make/verify_runtime_dependencies"
                        "make/emd2exml.in"))))
               (substitute* escripts
                 (("/usr/bin/env") (which "env"))))))
         (add-before 'configure 'set-erl-top
           (lambda _
             (setenv "ERL_TOP" (getcwd))))
         (add-after 'install 'patch-erl
           ;; This only works after install.
           (lambda* (#:key outputs #:allow-other-keys)
             (let ((out (assoc-ref outputs "out")))
               (substitute* (string-append out "/bin/erl")
                 (("basename") (which "basename"))
                 (("dirname") (which "dirname"))))))
         (add-after 'install 'install-doc
           (lambda* (#:key inputs outputs #:allow-other-keys)
             (let* ((out (assoc-ref outputs "out"))
                    (manpages (assoc-ref inputs "erlang-manpages"))
                    (share (string-append out "/share/")))
               (mkdir-p share)
               (with-directory-excursion share
                 (invoke "tar" "xvf" manpages))))))))
    (home-page "https://www.erlang.org/")
    (synopsis "The Erlang programming language")
    (description
     "Erlang is a programming language used to build massively
scalable soft real-time systems with requirements on high
availability.  Some of its uses are in telecoms, banking, e-commerce,
computer telephony and instant messaging.  Erlang's runtime system has
built-in support for concurrency, distribution and fault tolerance.")
    ;; Erlang is distributed under the Apache License 2.0, but some components
    ;; have other licenses. See 'system/COPYRIGHT' in the source distribution.
    (license (list license:asl2.0 license:bsd-2 license:bsd-3 license:expat
                   license:lgpl2.0+ license:tcl/tk license:zlib))))

(define-public emacs-erlang
  (package
    (name "emacs-erlang")
    (version (package-version erlang))
    (source (package-source erlang))
    (build-system emacs-build-system)
    (arguments
     `(#:phases
       (modify-phases %standard-phases
         (add-before 'expand-load-path 'change-working-directory
           (lambda _ (chdir "lib/tools/emacs") #t)))))
    (home-page "https://www.erlang.org/")
    (synopsis "Erlang major mode for Emacs")
    (description
     "This package provides an Emacs major mode for editing Erlang source
files.")
    (license license:asl2.0)))

(define-public erlang-base64url
  (package
    (name "erlang-base64url")
    (version "1.0.1")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "base64url" version))
              (sha256
               (base32
                "0p4zf53v86zfpnk3flinjnk6cx9yndsv960386qaj0hsfgaavczr"))))
    (build-system rebar-build-system)
    (home-page "https://github.com/dvv/base64url")
    (synopsis "URL-safe base64-compatible codec")
    (description "This package provides an URL-safe base64-compatible codec.")
    (license license:expat)))

(define-public erlang-bbmustache
  (package
    (name "erlang-bbmustache")
    (version "1.12.2")
    (source
     (origin
       (method url-fetch)
       (uri (hexpm-uri "bbmustache" version))
       (sha256
        (base32 "0fvvaxdpziygxl30j59g98qkh2n47xlb7w5dfpsm2bfcsnj372v8"))))
    (build-system rebar-build-system)
    (inputs
     (list erlang-getopt rebar3-git-vsn
           erlang-edown))  ; for building the docs
    (arguments
     `(#:tests? #f ;; requires mustache specification file
       #:phases
       (modify-phases %standard-phases
         (add-before 'build 'build-more
           (lambda _
             (invoke "rebar3" "as" "dev" "escriptize")))
         (add-after 'install 'install-escript
           (lambda* (#:key outputs #:allow-other-keys)
             (let* ((out (assoc-ref outputs "out")))
               (install-file "_build/dev/bin/bbmustache"
                             (string-append out "/bin"))))))))
    (home-page "https://github.com/soranoba/bbmustache/")
    (synopsis "Binary pattern match Based Mustache template engine for Erlang")
    (description "This Erlang library provides a Binary pattern match Based
Mustache template engine")
    (license license:expat)))

(define-public erlang-bear
  (package
    (name "erlang-bear")
    (version "1.0.0")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "bear" version))
              (sha256
               (base32
                "1nsri73b50n5v1a8252mm8car84j2b53bq7alq6zz16z3a86fyqm"))))
    (build-system rebar-build-system)
    (home-page "https://github.com/folsom-project/bear")
    (synopsis "Statistics functions for Erlang")
    (description "This package provides a set of statistics functions for
Erlang.")
    (license license:asl2.0)))

(define-public erlang-cache-tab
  (package
    (name "erlang-cache-tab")
    (version "1.0.30")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "cache_tab" version))
              (sha256
               (base32
                "186d642wlxc4bj9n3vgkjn2dad1fn3nxp9h6fxi44k7qv005x2kd"))))
    (build-system rebar-build-system)
    (inputs (list erlang-p1-utils))
    (home-page "https://github.com/processone/cache_tab/")
    (synopsis "In-memory cache Erlang / Elixir library")
    (description
     "The @code{cache_tab} application is intended to proxy
back-end operations for Key-Value insert, lookup and delete and maintain a
cache of those Key-Values in-memory, to save back-end operations.

Operations are intended to be atomic between back-end and cache tables.

The lifetime of the cache object and the max size of the cache can be defined
as table parameters to limit the size of the in-memory tables.")
    (license license:asl2.0)))

(define-public erlang-certifi
  (package
    (name "erlang-certifi")
    (version "2.9.0")
    (source
     (origin
       (method url-fetch)
       (uri (hexpm-uri "certifi" version))
       (sha256
        (base32 "0ha6vmf5p3xlbf5w1msa89frhvfk535rnyfybz9wdmh6vdms8v96"))))
    (build-system rebar-build-system)
    (arguments
     `(#:tests? #f)) ;; have not been updated for latest cert bundle
    (home-page "https://github.com/certifi/erlang-certifi/")
    (synopsis "Erlang CA certificate bundle")
    (description "This Erlang library contains a CA bundle that you can
reference in your Erlang application.  This is useful for systems that do not
have CA bundles that Erlang can find itself, or where a uniform set of CAs is
valuable.

This an Erlang specific port of certifi.  The CA bundle is derived from
Mozilla's canonical set.")
    (license license:bsd-3)))

(define-public erlang-cf
  (package
    (name "erlang-cf")
    (version "0.3.1")
    (source
     (origin
       (method url-fetch)
       (uri (hexpm-uri "cf" version))
       (sha256
        (base32 "0wknz4xkqkhgvlx4vx5619p8m65v7g87lfgsvfy04jrsgm28spii"))))
    (build-system rebar-build-system)
    (home-page "https://github.com/project-fifo/cf")
    (synopsis "Terminal colour helper for Erlang io and io_lib")
    (description "This package provides a helper library for termial colour
printing extending the io:format syntax to add colours.")
    (license license:expat)))

(define-public erlang-yamerl
  (package
    (name "erlang-yamerl")
    (version "0.10.0")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             ;; There are no tests included on Hex.
             (url "https://github.com/yakaz/yamerl")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "0if8abgmispcfk7zhd0a5dndzwzbsmqrbyrm5shk375r2dbbwak6"))))
    (build-system rebar-build-system)
    (synopsis "YAML and JSON parser in pure Erlang")
    (description
     "Erlang application to parse YAML 1.1 and YAML 1.2 documents, as well as
JSON documents.")
    (home-page "https://hexdocs.pm/yamerl/")
    (license license:bsd-2)))

(define-public erlang-covertool
  (package
    (name "erlang-covertool")
    (version "2.0.4")
    (source
     (origin
       (method url-fetch)
       (uri (hexpm-uri "covertool" version))
       (sha256
        (base32 "1p0c1n3nl4063xwi1sv176l1x68xqf07qwvj444a5z888fx6i5aw"))))
    (build-system rebar-build-system)
    (home-page "https://github.com/covertool/covertool")
    (synopsis "Convert code-coverage data generated by @code{cover} into
Cobertura XML reports")
    (description "This package provides a build tool and plugin to convert
exported Erlang @code{cover} data sets into Cobertura XML reports, which can
then be feed to the Jenkins Cobertura plug-in.

On @emph{hex.pm}, this plugin was previously called @code{rebar_covertool}.")
    (license license:bsd-2)))

(define-public erlang-cth-readable
  (package
    (name "erlang-cth-readable")
    (version "1.5.1")
    (source
     (origin
       (method url-fetch)
       (uri (hexpm-uri "cth_readable" version))
       (sha256
        (base32 "104xgybb6iciy6i28pyyrarqzliddi8kjyq43ajaav7y5si42rb8"))))
    (build-system rebar-build-system)
    (propagated-inputs
     (list erlang-cf))
    (arguments
     `(#:tests? #f)) ;; no test-suite in hex-pm package
    (home-page "https://github.com/ferd/cth_readable")
    (synopsis "Common Test hooks for more readable logs for Erlang")
    (description "This package provides an OTP library to be used for CT log
outputs you want to be readable around all that noise they contain.")
    (license license:bsd-3)))

(define-public erlang-edown
  (package
    (name "erlang-edown")
    (version "0.8.4")
    (source
      (origin
        (method url-fetch)
        (uri (hexpm-uri "edown" version))
        (sha256
          (base32 "0ij47gvgs6yfqphj0f54qjzj18crj8y1dsjjlzpp3dp8pscqzbqw"))))
    (build-system rebar-build-system)
    (home-page "https://github.com/uwiger/edown")
    (synopsis "Markdown extension for EDoc")
    (description "This package provides an extension for EDoc for generating
Markdown.")
    (license license:asl2.0)))

(define-public erlang-erlang-color
  (package
    (name "erlang-erlang-color")
    (version "1.0.0")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "erlang_color" version))
              (sha256
               (base32
                "0f707vxihn3f9m3zxal38ajcihnfcwms77jcax0gbzn8i7jya5vb"))))
    (build-system rebar-build-system)
    (home-page "https://github.com/julianduque/erlang-color")
    (synopsis "ANSI colors for Erlang")
    (description "This package provides ANSI colors for Erlang.")
    (license license:expat)))

(define-public erlang-eimp
  (package
    (name "erlang-eimp")
    (version "1.0.22")
    (source
      (origin
        (method git-fetch)  ;; package at hex.pm is missing the Makefile
        (uri (git-reference
              (url "https://github.com/processone/eimp")
              (commit version)))
       (file-name (git-file-name name version))
        (sha256
          (base32 "1d480w2p5ax29fl7q2p90zjwa18nbaxczcrajfrhx5hqja1lxcvc"))))
    (build-system rebar-build-system)
    ;; (native-inputs
    ;;  `(("erlang" ,erlang)
    ;;    ("rebar3" ,rebar3)))
    (inputs (list erlang-p1-utils gd libjpeg-turbo libpng libwebp))
    (arguments
     `(;;#:modules (;;(srfi srfi-19) ; make-time, et cetera.
       ;;           (guix build utils)
       ;;           (guix build gnu-build-system)
       ;;           ((guix build rebar-build-system) #:prefix rebar:))
       ;; #:imported-modules (;;(guix build rebar-build-system)
       ;;                     ;;(guix build syscalls)
       ;;                     ,@%rebar-build-system-modules
       ;;                     ,@%gnu-build-system-modules)
       #:phases
       (modify-phases %standard-phases
         (add-before 'build 'configure-compiler
           (lambda _
             (setenv "CC" "gcc")
             #t))
         ;; (replace 'unpack
         ;;   (assoc-ref rebar:%standard-phases 'unpack))
         ;; (replace 'build
         ;;   (lambda _
         ;;     ;;(setenv "CC" "gcc")
         ;;     (invoke "rebar3" "compile")))
         ;; (add-before 'build 'depends
         ;;   (assoc-ref rebar:%standard-phases 'erlang-depends))
         )))
    (home-page "https://github.com/processone/eimp/")
    (synopsis "Erlang/Elixir image converter")
    (description "@code{eimp} is an Erlang/Elixir application for manipulating
graphic images using external C libraries.  It supports WebP, JPEG, PNG and
GIF.")
    (license license:asl2.0)))

(define-public erlang-erlware-commons
  (package
    (name "erlang-erlware-commons")
    (version "1.6.0")
    (source
     (origin
       (method url-fetch)
       (uri (hexpm-uri "erlware_commons" version))
       (sha256
        (base32 "18qam9xdzi74wppb0cj4zc8161i0i8djr79z8662m6d276f2jz5m"))))
    (build-system rebar-build-system)
    (propagated-inputs
     (list erlang-cf))
    (native-inputs
     (list git-minimal/pinned))  ;; Required for tests
    (arguments
     `(#:phases
       (modify-phases %standard-phases
         (add-before 'check 'check-setup
           (lambda _
             (setenv "TERM" "xterm")))))) ; enable color in logs
    (home-page "https://erlware.github.io/erlware_commons/")
    (synopsis "Additional standard library for Erlang")
    (description "Erlware Commons is an Erlware project focused on all aspects
of reusable Erlang components.")
    (license license:expat)))

(define-public erlang-esip
  (package
    (name "erlang-esip")
    (version "1.0.47")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "esip" version))
              (sha256
               (base32
                "0glgzs8rj2cmvcrklbjpx036868w2n3m0z0lrcj5ncldkv207rwr"))))
    (build-system rebar-build-system)
    (inputs (list erlang-fast-tls erlang-p1-utils erlang-stun))
    (home-page "https://github.com/processone/esip")
    (synopsis "SIP server component in Erlang")
    (description "This package provides a SIP (Session Initiation Protocol)
server component in Erlang.")
    (license license:asl2.0)))

(define-public erlang-eunit-formatters
  (package
    (name "erlang-eunit-formatters")
    (version "0.5.0")
    (source
     (origin
       (method url-fetch)
       (uri (hexpm-uri "eunit_formatters" version))
       (sha256
        (base32 "1jb3hzb216r29x2h4pcjwfmx1k81431rgh5v0mp4x5146hhvmj6n"))))
    (build-system rebar-build-system)
    (home-page "https://github.com/seancribbs/eunit_formatters")
    (synopsis "Better output for eunit suites")
    (description "This package provides a better output for Erlang eunits.")
    (license license:asl2.0)))

(define-public erlang-ezlib
  (package
    (name "erlang-ezlib")
    (version "1.0.12")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "ezlib" version))
              (sha256
               (base32
                "1fsf3rbffq47ykm8lp35br8k7wkbqnq2qn0jdsmhl9j2zdal7s9h"))))
    (build-system rebar-build-system)
    (arguments
     `(#:phases
       (modify-phases %standard-phases
         (add-before 'build 'build-setup
           (lambda _
             (setenv "DEBUG" "1")
             (setenv "HOME" "/tmp"))))))
    (inputs (list erlang-pc))
    (home-page "https://github.com/processone/ezlib/")
    (synopsis "Native zlib driver for Erlang / Elixir")
    (description "This library focuses on compression / decompression of data
streams.")
    (license license:asl2.0)))

(define-public erlang-fast-tls
  (package
    (name "erlang-fast-tls")
    (version "1.1.15")
    (source (origin
              ;; Source tarball on hex.pm lacks "tests" directory
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/processone/fast_tls")
                    (commit version)))
              (file-name (git-file-name name version))
              (sha256
               (base32
                "14a7hd34vh30zwv9dvqjsmsdvra7sgdn0aq4vmblc8r1ayhlc74k"))))
    (build-system rebar-build-system)
    (inputs (list erlang-p1-utils openssl))
    (home-page "https://github.com/processone/fast_tls")
    (synopsis "TLS / SSL OpenSSL-based native driver for Erlang / Elixir")
    (description
     "Fast TLS is a native TLS / SSL driver for Erlang /
Elixir.  It is based on OpenSSL, a proven and efficient TLS implementation.
It is designed for efficiency, speed and compliance.")
    (license license:asl2.0)))

(define-public erlang-fast-xml
  (package
    (name "erlang-fast-xml")
    (version "1.1.49")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "fast_xml" version))
              (sha256
               (base32
                "14rmi1vxr43z45199awapwbmqiz2zqvnc0v1d6aih23l5x6hdnh1"))))
    (build-system rebar-build-system)
    (inputs (list erlang-p1-utils))
    (home-page "https://hex.pm/packages/fast_xml/")
    (synopsis "Fast Expat-based Erlang / Elixir XML parsing library")
    (description
     "This package provides a fast, Expat based Erlang XML parsing
and manipulation library, with a strong focus on XML stream parsing from
network.
It supports:
@itemize
@item Full XML structure parsing: Suitable for small but complete XML chunks.
@item XML stream parsing: Suitable for large XML document, or infinite network
XML stream like XMPP.
@end itemize")
    (license license:asl2.0)))

(define-public erlang-fast-yaml
  (package
    (name "erlang-fast-yaml")
    (version "1.0.33")
    (source (origin
              ;; Source tarball on hex.pm lacks "tests" directory
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/processone/fast_yaml")
                    (commit version)))
              (file-name (git-file-name name version))
              (sha256
               (base32
                "1mws3rgd83s1wfx8gi3bwnj93486z1rgf6k85sx93ynnk1xfl989"))))
    (build-system rebar-build-system)
    (inputs (list libyaml erlang-p1-utils))
    (home-page "https://github.com/processone/fast_yaml/")
    (synopsis "Fast YAML native library for Erlang / Elixir")
    (description "``Fast YAML'' is an Erlang wrapper for libyaml C library.
It is designed to be fast and efficient.")
    (license license:asl2.0)))

(define-public erlang-folsom
  (package
    (name "erlang-folsom")
    (version "1.0.0")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "folsom" version))
              (sha256
               (base32
                "03mvxvrpfl800x896bnxq2p7x33v98i8iqa3zi69wkz9g1rbjsnx"))))
    (build-system rebar-build-system)
    (inputs (list erlang-bear erlang-meck erlang-proper))
    (home-page "https://github.com/folsom-project/folsom")
    (synopsis "Erlang based metrics system")
    (description
     "Folsom is an Erlang based metrics system inspired by Coda
Hale's metrics.  The metrics API's purpose is to collect realtime metrics from
your Erlang applications and publish them via Erlang APIs and output
plugins. @code{folsom} is not a persistent store.  There are 6 types of
metrics: counters, gauges, histograms (and timers), histories, meter_readers
and meters.  Metrics can be created, read and updated via the folsom_metrics
module.")
    (license license:asl2.0)))

(define-public erlang-getopt
  (package
    (name "erlang-getopt")
    (version "1.0.2")
    (source
     (origin
       (method url-fetch)
       (uri (hexpm-uri "getopt" version))
       (sha256
        (base32 "09pasi7ki1rivw9sl7xndj5qgjbdqvcscxk83yk85yr28gm9l0m0"))))
    (build-system rebar-build-system)
    (home-page "https://github.com/jcomellas/getopt")
    (synopsis "Command-line options parser for Erlang")
    (description "This package provides an Erlang module to parse command line
arguments using the GNU getopt syntax.")
    (license license:bsd-3)))

(define-public erlang-goldrush
  (package
    (name "erlang-goldrush")
    (version "0.1.9")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "goldrush" version))
              (sha256
               (base32
                "1ssck5yr7rnrfwzm55pbyi1scgs1sl1xim75h5sj5czwrwl43jwr"))))
    (build-system rebar-build-system)
    (home-page "https://github.com/DeadZen/goldrush")
    (synopsis "Erlang event stream processor")
    (description "Erlang event stream processor")
    (license license:isc)))

(define-public erlang-hackney
  (package
    (name "erlang-hackney")
    (version "1.18.1")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "hackney" version))
              (sha256
               (base32
                "13hja14kig5jnzcizpdghj68i88f0yd9wjdfjic9nzi98kzxmv54"))))
    (build-system rebar-build-system)
    (arguments
     `(#:phases (modify-phases %standard-phases
                  (add-before 'build 'configure-compiler
                    (lambda _
                      (setenv "DEBUG" "1")
                      (setenv "HOME" "/tmp") #t)))))
    (inputs (list erlang-certifi
                  erlang-cowboy
                  erlang-idna
                  erlang-jsone
                  erlang-metrics
                  erlang-mimerl
                  erlang-parse-trans
                  erlang-ssl-verify-fun
                  erlang-unicode-util-compat))
    (home-page "https://github.com/benoitc/hackney")
    (synopsis "Simple HTTP client")
    (description "This package provides a HTTP client library for Erlang.")
    (license license:asl2.0)))

(define-public erlang-hex-core
  (package
    (name "erlang-hex-core")
    (version "0.8.4")
    (source
     (origin
       (method url-fetch)
       (uri (hexpm-uri "hex_core" version))
       (sha256
        (base32 "06p65hlm29ky03vs3fq3qz6px2ylwp8b0f2y75wdf5cm0kx2332b"))))
    (build-system rebar-build-system)
    (arguments
     `(#:phases
       (modify-phases %standard-phases
         (replace 'check
           (lambda* (#:key tests? #:allow-other-keys)
             (when tests?
               (invoke "rebar3" "as" "test" "proper")))))))
    (inputs
     (list erlang-proper rebar3-proper))
    (home-page "https://github.com/hexpm/hex_core")
    (synopsis "Reference implementation of Hex specifications")
    (description "This package provides the reference implementation of Hex
specifications.")
    (license license:asl2.0)))

(define-public erlang-jiffy
  (package
    (name "erlang-jiffy")
    (version "1.1.1")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "jiffy" version))
              (sha256
               (base32
                "0k2wg2s8c8jmla2kiz5s3gzqn3a1i3x1sy2wf8xc669w3icg1qb2"))))
    (build-system rebar-build-system)
    (arguments
     `(#:phases (modify-phases %standard-phases
                  (add-before 'build 'configure-compiler
                    (lambda _
                      (setenv "CC" "gcc") #t)))))
    (home-page "https://github.com/davisp/jiffy")
    (synopsis "JSON Decoder/Encoder")
    (description
     "A JSON parser as a NIF.  This is a complete rewrite of the
work I did in EEP0018 that was based on Yajl.  This new version is a hand
crafted state machine that does its best to be as quick and efficient as
possible while not placing any constraints on the parsed JSON.")
    (license (list license:expat license:bsd-3))))

(define-public erlang-jose
  (package
    (name "erlang-jose")
    (version "1.11.2")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "jose" version))
              (sha256
               (base32
                "1lj715gzl022yc47qsg9712x8nc9wi7x70msv8c3lpym92y3y54q"))))
    (build-system rebar-build-system)
    (home-page "https://github.com/potatosalad/erlang-jose")
    (synopsis "JSON Object Signing and Encryption for Erlang and Elixir")
    (description
     "This package provides JSON Object Signing and
Encryption (JOSE).  JOSE is a set of standards established by the JOSE Working
Group.")
    (license license:expat)))

(define-public erlang-idna
  (package
    (name "erlang-idna")
    (version "6.1.1")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "idna" version))
              (sha256
               (base32
                "1sjcjibl34sprpf1dgdmzfww24xlyy34lpj7mhcys4j4i6vnwdwj"))))
    (build-system rebar-build-system)
    (inputs (list erlang-unicode-util-compat))
    (home-page "https://hex.pm/packages/idna/")
    (synopsis "Pure Erlang IDNA implementation")
    (description "This package provides a pure Erlang IDNA implementation.")
    (license license:expat)))

(define-public erlang-jsone
  (package
    (name "erlang-jsone")
    (version "1.7.0")
    (source
      (origin
        (method url-fetch)
        (uri (hexpm-uri "jsone" version))
        (sha256
          (base32 "1gaxiw76syjp3s9rygskm32y9799b917q752rw8bxj3bxq93g8x3"))))
    (build-system rebar-build-system)
    (arguments
     `(#:phases
       (modify-phases %standard-phases
         (add-after 'unpack 'disable-covertool
           ;; no need to generate a coverage report
           (lambda _
             (substitute* "rebar.config"
               (("\\{project_plugins, \\[covertool\\]\\}\\." _) "")))))))
    (home-page "https://github.com/sile/jsone/")
    (synopsis "Erlang JSON Library")
    (description "An Erlang library for encoding and decoding JSON data.")
    (license license:expat)))

(define-public erlang-lager
  (package
    (name "erlang-lager")
    (version "3.9.2")
    (source (origin
              ;; Source tarball on hex.pm lacks test directory.
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/erlang-lager/lager")
                    (commit version)))
              (file-name (git-file-name name version))
              (sha256
               (base32
                "0sxqb7fxa95m9019a0fmzp0220wsfr0xmzw965mzkg0xl5qq2p4m"))
              (modules '((guix build utils)))
              (snippet '(begin
                          (delete-file "rebar") #t))))
    (build-system rebar-build-system)
    (inputs (list erlang-goldrush))
    (home-page "https://github.com/erlang-lager/lager")
    (synopsis "Erlang logging framework")
    (description
     "Lager (as in the beer) is a logging framework for Erlang.
Its purpose is to provide a more traditional way to perform logging in an
erlang application that plays nicely with traditional UNIX logging tools like
logrotate and syslog.")
    (license license:asl2.0)))

(define-public erlang-meck
  (package
    (name "erlang-meck")
    (version "0.9.2")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "meck" version))
              (sha256
               (base32
                "09jq0jrsd3dwzjlnwqjv6m9r2rijgiv57yja6jl41p2p2db4yd41"))))
    (build-system rebar-build-system)
    (inputs (list erlang-unite))
    (home-page "https://github.com/eproxus/meck")
    (synopsis "Mocking framework for Erlang")
    (description "This package provides a mocking framework for Erlang.")
    (license license:asl2.0)))

(define-public erlang-metrics
  (package
    (name "erlang-metrics")
    (version "2.5.0")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "metrics" version))
              (sha256
               (base32
                "0jviygsq88x6hymrhrg1zwg1wp71ccmpk6my2xyykgf3r0w1j1mf"))))
    (build-system rebar-build-system)
    (inputs (list erlang-exometer-core))
    (home-page "https://github.com/benoitc/erlang-metrics")
    (synopsis "Generic interface to different metrics systems in Erlang")
    (description "This package provides a generic interface to different
metrics systems in Erlang.")
    (license license:bsd-3)))

(define-public erlang-mimerl
  (package
    (name "erlang-mimerl")
    (version "1.2.0")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "mimerl" version))
              (sha256
               (base32
                "08wkw73dy449n68ssrkz57gikfzqk3vfnf264s31jn5aa1b5hy7j"))))
    (build-system rebar-build-system)
    (home-page "https://github.com/benoitc/mimerl")
    (synopsis "Library to handle mimetypes")
    (description "This package provides a library to handle mime-types.")
    (license license:expat)))

(define-public erlang-mqtree
  (package
    (name "erlang-mqtree")
    (version "1.0.15")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "mqtree" version))
              (sha256
               (base32
                "0afqp5ircqqs81faar7zvhi5arcww5cw4mpaxqj2wdrxkcyc8ji9"))))
    (build-system rebar-build-system)
    (inputs (list erlang-p1-utils))
    (home-page "https://hex.pm/packages/mqtree/")
    (synopsis "Index tree for MQTT topic filters")
    (description "Index tree for MQTT topic filters")
    (license license:asl2.0)))

(define-public erlang-p1-acme
  (package
    (name "erlang-p1-acme")
    (version "1.0.19")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "p1_acme" version))
              (sha256
               (base32
                "032mgg6729bd4dh4npj4abyvl2nkfq36g99v3xfpimd17h126h4h"))))
    (build-system rebar-build-system)
    (inputs (list erlang-idna erlang-jiffy erlang-jose erlang-yconf))
    (home-page "https://github.com/processone/p1_acme")
    (synopsis "Erlang ACME client")
    (description "This package provides an Erlang ACME client (RFC8555).")
    (license license:asl2.0)))

(define-public erlang-p1-mysql
  (package
    (name "erlang-p1-mysql")
    (version "1.0.19")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "p1_mysql" version))
              (sha256
               (base32
                "1c92jsa6gnj1hffqb3r277i3szln0kdcr15fnqa9r5g822swvxl8"))))
    (build-system rebar-build-system)
    (home-page "https://hex.pm/packages/p1_mysql/")
    (synopsis "Pure Erlang MySQL driver")
    (description "This package provides a pure Erlang MySQL driver.")
    (license (list license:bsd-3 license:asl2.0))))

(define-public erlang-p1-oauth2
  (package
    (name "erlang-p1-oauth2")
    (version "0.6.11")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "p1_oauth2" version))
              (sha256
               (base32
                "1nv33z6jmnagb48dpxlm7zrhi64894ls60mvfda55fc2jgjnlg4w"))))
    (build-system rebar-build-system)
    (home-page "https://hex.pm/packages/p1_oauth2/")
    (synopsis "Erlang OAuth 2.0 implementation")
    (description "This package provides an Erlang OAuth 2.0 implementation.")
    (license (list license:expat license:asl2.0))))

(define-public erlang-p1-pgsql
  (package
    (name "erlang-p1-pgsql")
    (version "1.1.18")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "p1_pgsql" version))
              (sha256
               (base32
                "0ipx4lmxm5qh6xs4ldij37rysd1x9rypljf8zrj9zvczsnjn6f2a"))))
    (build-system rebar-build-system)
    (home-page "https://github.com/processone/p1_pgsql/")
    (synopsis "PostgreSQL driver")
    (description "This package provides a pure Erlang PostgreSQL driver.")
    (license (list license:mpl1.0 ;Erlang Public License v1.1 ErlPL1.1
                   license:asl2.0))))

(define-public erlang-p1-utils
  (package
    (name "erlang-p1-utils")
    (version "1.0.25")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "p1_utils" version))
              (sha256
               (base32
                "0ir8lfnhf3l4b6ifj2s24wj5qsc3hydfpy3z339ybipj512226cj"))))
    (build-system rebar-build-system)
    (propagated-inputs (list erlang-pc))
    (home-page "https://github.com/processone/p1_utils/")
    (synopsis "Erlang utility modules from ProcessOne")
    (description
     "@code{p1_utils} is an application containing ProcessOne
modules and tools that are leveraged in other development projects.")
    (license license:asl2.0)))

(define-public erlang-parse-trans
  (package
    (name "erlang-parse-trans")
    (version "3.4.1")
    (source
     (origin
       (method url-fetch)
       (uri (hexpm-uri "parse_trans" version))
       (sha256
        (base32 "16p4c2xjrvz16kzpr9pmcvi6nxq6rwckqi9fp0ksibaxwxn402k2"))))
    (build-system rebar-build-system)
    (inputs
     (list erlang-getopt))
    (home-page "https://github.com/uwiger/parse_trans")
    (synopsis "Parse transform utilities for Erlang")
    (description "This package captures some useful patterns in parse
transformation and code generation for Erlang.

For example generating standardized accessor functions for records or
evaluating an expression at compile-time and substitute the result as a
compile-time constant.")
    (license license:asl2.0)))

(define-public erlang-pc
  (package
    (name "erlang-pc")
    (version "1.14.0")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "pc" version))
              (sha256
               (base32
                "0lrmk905xnvjfsjjmycvhkkrvq1b4slgmvmswqalcwdgar9pwngw"))))
    (build-system rebar-build-system)
    (arguments
     `(#:phases (modify-phases %standard-phases
                  (add-after 'unpack 'patch-path
                    (lambda* (#:key inputs #:allow-other-keys)
                      (let ((gcc (assoc-ref inputs "gcc")))
                        (substitute* "src/pc_port_env.erl"
                          (("(get_tool.* \")cc(\"\\)})" _ pre post) (string-append
                                                                     pre "gcc"
                                                                     post)))
                        (substitute* "src/pc_util.erl"
                          (("(^ +Compiler = .* \")cc(\";)" _ pre post) (string-append
                                                                        pre
                                                                        gcc
                                                                        "/bin/gcc"
                                                                        post)))))))))
    (home-page "https://github.com/blt/port_compiler")
    (synopsis "Rebar3 port compiler for native code")
    (description "This package provides a rebar3 port compiler for native
code.")
    (license license:expat)))

(define-public erlang-pkix
  (package
    (name "erlang-pkix")
    (version "1.0.9")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "pkix" version))
              (sha256
               (base32
                "0fiy203vfn9fgqvy2aa9cckmy6jak47c19a5kdfa1vflrl4jrays"))))
    (build-system rebar-build-system)
    (home-page "https://github.com/processone/pkix")
    (synopsis "PKIX certificates management library for Erlang")
    (description
     "This library simplifies certificates configuration in Erlang
programs.  It reduces a user configuration to something as simple providing a
path pattern/glob for specifying the certicicate files.")
    (license license:asl2.0)))

(define-public erlang-proper
  (package
    (name "erlang-proper")
    (version "1.4.0")
    (source
      (origin
        (method url-fetch)
        (uri (hexpm-uri "proper" version))
        (sha256
          (base32 "1fwcas4a9kz3w3z1jqdk9lw8822srfjk9lcpvbxkxlsv3115ha0q"))))
    (build-system rebar-build-system)
    (arguments
     `(#:phases
       (modify-phases %standard-phases
         (add-after 'unpack 'disable-covertool
           ;; no need to generate a coverage report
           (lambda _
             (substitute* "rebar.config"
               (("\\{plugins, \\[covertool\\]\\}\\." _) "")))))))
    (home-page "https://proper-testing.github.io/")
    (synopsis "QuickCheck-inspired property-based testing tool for Erlang")
    (description "PropEr is a tool for the automated, semi-random,
property-based testing of Erlang programs.  It is fully integrated with
Erlang's type language, and can also be used for the model-based random
testing of stateful systems.")
    (license license:gpl3+)))

(define-public erlang-jsx
  (package
    (name "erlang-jsx")
    (version "3.1.0")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "jsx" version))
              (sha256
               (base32
                "1wr7jkxm6nlgvd52xhniav64xr9rml2ngb35rwjwqlqvq7ywhp0c"))))
    (build-system rebar-build-system)
    (synopsis "Streaming, evented JSON parsing toolkit")
    (description
     "An Erlang application for consuming, producing and manipulating json.")
    (home-page "https://github.com/talentdeficit/jsx")
    (license license:expat)))

(define-public erlang-providers
  (package
    (name "erlang-providers")
    (version "1.9.0")
    (source
     (origin
       (method url-fetch)
       (uri (hexpm-uri "providers" version))
       (sha256
        (base32 "05y0kz3xgx77hzn1l05byaisvmk8bgds7c22hrh0a5ba81sfi1yj"))))
    (build-system rebar-build-system)
    (propagated-inputs
     (list erlang-erlware-commons erlang-getopt))
    (home-page "https://github.com/tsloughter/providers")
    (synopsis "Erlang providers library")
    (description "This package provides an Erlang providers library.")
    (license license:asl2.0)))

(define-public erlang-provider-asn1
  (package
    (name "erlang-provider-asn1")
    (version "0.3.0")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "provider_asn1" version))
              (sha256
               (base32
                "01gvpwdlkpmvzi280rn66f5ijlvap6k368yzpb0mmlv2hrcsbrrj"))))
    (build-system rebar-build-system)
    (home-page "https://github.com/knusbaum/provider_asn1/")
    (synopsis "Compile ASN.1 with Rebar3")
    (description
     "This package provides a plugin to compile ASN.1 with Rebar3.")
    (license license:expat)))

(define-public erlang-relx
  (package
    (name "erlang-relx")
    (version "4.6.0")
    (source
     (origin
       (method url-fetch)
       (uri (hexpm-uri "relx" version))
       (sha256
        (base32 "02gmfx1vxg9m3mq4njsqhs4972l4nb8m5p1pdcf64g09ccf17y1g"))))
    (build-system rebar-build-system)
    (propagated-inputs
     (list erlang-bbmustache))
    (home-page "https://erlware.github.io/relx/")
    (synopsis "Release assembler for Erlang/OTP Releases")
    (description "Relx assembles releases for an Erlang/OTP release.  Given a
release specification and a list of directories in which to search for OTP
applications it will generate a release output.  That output depends heavily on
what plugins available and what options are defined, but usually it is simply
a well configured release directory.")
    (license license:asl2.0)))

(define-public erlang-ssl-verify-fun
  (package
    (name "erlang-ssl-verify-fun")
    (version "1.1.6")
    (source
     (origin
       (method url-fetch)
       (uri (hexpm-uri "ssl_verify_fun" version))
       (sha256
        (base32 "1026l1z1jh25z8bfrhaw0ryk5gprhrpnirq877zqhg253x3x5c5x"))))
    (build-system rebar-build-system)
    (home-page "https://github.com/deadtrickster/ssl_verify_fun.erl")
    (synopsis "SSL verification functions for Erlang")
    (description "This package provides SSL verification functions for
Erlang.")
    (license license:expat)))

(define-public erlang-unicode-util-compat
  (package
    (name "erlang-unicode-util-compat")
    (version "0.7.0")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "unicode_util_compat" version))
              (sha256
               (base32
                "08952lw8cjdw8w171lv8wqbrxc4rcmb3jhkrdb7n06gngpbfdvi5"))))
    (build-system rebar-build-system)
    (home-page "https://github.com/benoitc/unicode_util_compat")
    (synopsis "Unicode_util compatibility library for Erlang < 20")
    (description "This package provides a @code{unicode_util} compatibility
library for Erlang < 20.")
    (license license:asl2.0)))

(define-public erlang-stringprep
  (package
    (name "erlang-stringprep")
    (version "1.0.28")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "stringprep" version))
              (sha256
               (base32
                "1q382nka19qvxq25xnr8918h749n7wjh13dx4k49kj7yh48pvpv6"))))
    (build-system rebar-build-system)
    (inputs (list erlang-p1-utils))
    (home-page "https://hex.pm/packages/stringprep/")
    (synopsis "Fast Stringprep Erlang / Elixir implementation")
    (description "This package provides a fast Stringprep Erlang / Elixir
implementation.")
    (license (list license:asl2.0 license:tcl/tk))))

(define-public erlang-stun
  (package
    (name "erlang-stun")
    (version "1.2.2")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "stun" version))
              (sha256
               (base32
                "1fd3s9gl0jy4d8zca8d70qf1wis8j1lzpa9mxkx1791adswcfm2g"))))
    (build-system rebar-build-system)
    (inputs (list erlang-fast-tls erlang-p1-utils))
    (home-page "https://hex.pm/packages/stun/")
    (synopsis "STUN and TURN library for Erlang / Elixir")
    (description "This package provides a STUN and TURN library for Erlang /
Elixir.")
    (license license:asl2.0)))

(define-public erlang-yconf
  (package
    (name "erlang-yconf")
    (version "1.0.13")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "yconf" version))
              (sha256
               (base32
                "0lfqhampqww6g3fvpny3nv30lqf3ai8qya44jqi2389x5chpim1z"))))
    (build-system rebar-build-system)
    (inputs (list erlang-fast-yaml))
    (home-page "https://hex.pm/packages/yconf/")
    (synopsis "YAML configuration processor")
    (description "YAML configuration processor")
    (license license:asl2.0)))

(define-public erlang-xmpp
  (package
    (name "erlang-xmpp")
    (version "1.5.8")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "xmpp" version))
              (sha256
               (base32
                "0jjvh9zi3qmy6nfng41s61s5ibq2bp6sr7l0pq816cx7vqwlasln"))))
    (build-system rebar-build-system)
    (inputs (list erlang-ezlib
                  erlang-fast-tls
                  erlang-fast-xml
                  erlang-idna
                  erlang-p1-utils
                  erlang-provider-asn1))
    (home-page "https://github.com/processone/xmpp/")
    (synopsis "Erlang/Elixir XMPP parsing and serialization library")
    (description
     "The library provides comprehensive representation of XMPP
elements as well as tools to work with them.  Every such element is
represented by an Erlang record.  Most of the library's code is auto generated
and thus considered to be bug free and efficient.")
    (license license:asl2.0)))

(define-public rebar3
  (package
    (name "rebar3")
    (version "3.18.0")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/erlang/rebar3")
             (commit version)))
       (file-name (git-file-name name version))
       (sha256
        (base32 "09648hzc2mnjwf9klm20cg4hb5rn2xv2gmzcg98ffv37p5yfl327"))))
    (build-system gnu-build-system)
    ;; TODO: remove vendored modules, install man-page, install lib(?)
    (arguments
     `(#:phases
       (modify-phases %standard-phases
         (delete 'bootstrap)
         (add-after 'unpack 'unpack-dependency-sources
           (lambda* (#:key inputs #:allow-other-keys)
             (for-each
              (lambda (pkgname)
                (let* ((src (string-append pkgname "-source"))
                       (input (assoc-ref inputs src))
                       (checkouts-dir (string-append "_checkouts/" pkgname))
                       (lib-dir (string-append "_build/default/lib/" pkgname)))
                  (mkdir-p checkouts-dir)
                  (invoke "tar" "-xf" input "-C" checkouts-dir)
                  (invoke "tar" "-xzf"
                          (pk (string-append checkouts-dir "/contents.tar.gz"))
                          "-C" checkouts-dir)
                  (mkdir-p lib-dir)
                  (copy-recursively checkouts-dir lib-dir)))
              (list "bbmustache" "certifi" "cf" "cth_readable"
                    "eunit_formatters" "getopt" "hex_core" "erlware_commons"
                    "parse_trans" "relx" "ssl_verify_fun" "providers"))))
         (delete 'configure)
         (replace 'build
           (lambda _
             (setenv "HOME" (getcwd))
             (invoke "./bootstrap")))
         (replace 'install
           (lambda* (#:key outputs #:allow-other-keys)
             (let* ((out (assoc-ref outputs "out")))
               (install-file "rebar3" (string-append out "/bin")))))
         (delete 'check))))
    (native-inputs
     (list erlang))
    (inputs
     `(("bbmustache-source" ,(package-source erlang-bbmustache))
       ("certifi-source" ,(package-source erlang-certifi))
       ("cf-source" ,(package-source erlang-cf))
       ("cth_readable-source" ,(package-source erlang-cth-readable))
       ("erlware_commons-source" ,(package-source erlang-erlware-commons))
       ("eunit_formatters-source" ,(package-source erlang-eunit-formatters))
       ("getopt-source" ,(package-source erlang-getopt))
       ("hex_core-source" ,(package-source erlang-hex-core))
       ("parse_trans-source" ,(package-source erlang-parse-trans))
       ("relx-source" ,(package-source erlang-relx))
       ("ssl_verify_fun-source" ,(package-source erlang-ssl-verify-fun))
       ("providers-source" ,(package-source erlang-providers))))
    (home-page "https://rebar3.org/")
    (synopsis "Sophisticated build-tool for Erlang projects that follows OTP
principles")
    (description "@code{rebar3} is an Erlang build tool that makes it easy to
compile and test Erlang applications, port drivers and releases.

@code{rebar3} is a self-contained Erlang script, so it's easy to distribute or
even embed directly in a project.  Where possible, rebar uses standard
Erlang/OTP conventions for project structures, thus minimizing the amount of
build configuration work.  @code{rebar3} also provides dependency management,
enabling application writers to easily re-use common libraries from a variety
of locations (git, hg, etc).")
    (license license:asl2.0)))

(define-public rebar3-raw-deps
  (package
    (name "rebar3-raw-deps")
    (version "2.0.0")
    (source
     (origin
       (method url-fetch)
       (uri (hexpm-uri "rebar3_raw_deps" version))
       (sha256
        (base32 "1pzmm3m8gb2s9jn8fp6shzgfmy4mvh2vdci0z6nsm74ma3ffh1i3"))))
    (build-system rebar-build-system)
    (home-page "https://github.com/soranoba/rebar3_raw_deps")
    (synopsis "Rebar3 plugin for supporting \"raw\" dependencies")
    (description "This plugin provides support for handling non-OTP
applications as a dependent libraries.")
    (license license:expat)))

(define-public rebar3-git-vsn
  (package
    (name "rebar3-git-vsn")
    (version "1.1.1")
    (source
      (origin
        (method url-fetch)
        (uri (hexpm-uri "rebar3_git_vsn" version))
        (sha256
          (base32 "1dfz56034pa25axly9vqdzv3phkn8ll0qwrkws96pbgcprhky1hx"))))
    (build-system rebar-build-system)
    (inputs
     (list git-minimal/pinned))
    (arguments
     `(;; Running the tests require binary artifact (tar-file containing
       ;; samples git repos)  TODO: remove these from the source
       #:tests? #f
       #:phases
       (modify-phases %standard-phases
         (add-after 'unpack 'patch-path
           (lambda* (#:key inputs #:allow-other-keys)
             (let ((git (assoc-ref inputs "git-minimal")))
               (substitute* "src/rebar3_git_vsn.erl"
                 (("rebar_utils:sh\\(\"git " _)
                  (string-append "rebar_utils:sh(\"" git "/bin/git ")))))))))
    (home-page "https://github.com/soranoba/rebar3_git_vsn")
    (synopsis "Rebar3 plugin for generating the version from git")
    (description "This plugin adds support for generating the version from
a git checkout.")
    (license license:expat)))

(define-public rebar3-proper
  (package
    (name "rebar3-proper")
    (version "0.12.1")
    (source
      (origin
        (method url-fetch)
        (uri (hexpm-uri "rebar3_proper" version))
        (sha256
          (base32 "1f174fb6h2071wr7qbw9aqqvnglzsjlylmyi8215fhrmi38w94b6"))))
    (build-system rebar-build-system)
    (home-page "https://github.com/ferd/rebar3_proper")
    (synopsis "Rebar3 PropEr plugin")
    (description "This plugin allows running PropEr test suites from within
rebar3.")
    (license license:bsd-3)))

(define-public erlang-lfe
  (package
    (name "erlang-lfe")
    (version "2.1.2")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/lfe/lfe")
                    (commit "v2.1.2")))
              (file-name (git-file-name name version))
              (sha256
               (base32
                "180hz1p2v3vb6yyzcfwircmljlnd86ln8z80lzy3mwlyrcxblvxy"))))
    (build-system gnu-build-system)
    (arguments
     (list
      #:modules '((ice-9 ftw)
                  (srfi srfi-26)
                  (guix build gnu-build-system)
                  (guix build utils))
      #:make-flags #~(list (string-append "PREFIX=" #$output) "CC=gcc")
      #:phases
      #~(modify-phases %standard-phases
          (delete 'configure)
          ;; The following is inspired by rebar-build-system.scm
          (add-before 'check 'erlang-depends
            (lambda* (#:key inputs #:allow-other-keys)
              (define input-directories
                (list #$(this-package-native-input "rebar3-proper")
                      #$(this-package-native-input "erlang-proper")))
              (mkdir-p "_checkouts")
              (for-each
               (lambda (input-dir)
                 (let ((elibdir (string-append input-dir "/lib/erlang/lib")))
                   (when (directory-exists? elibdir)
                     (for-each
                      (lambda (dirname)
                        (let ((src (string-append elibdir "/" dirname))
                              (dest (string-append "_checkouts/" dirname)))
                          (when (not (file-exists? dest))
                            ;; Symlinking will not work, since rebar3 will try
                            ;; to overwrite the _build directory several times
                            ;; with the contents of _checkout, so we copy the
                            ;; directory tree to _checkout and make it
                            ;; writable.
                            (copy-recursively src dest #:follow-symlinks? #t)
                            (for-each (cut chmod <> #o777)
                                      (find-files dest)))))
                      (scandir elibdir (lambda (file)
                                         (and (not (member file '("." "..")))
                                              (file-is-directory?
                                               (string-append elibdir
                                                              "/"
                                                              file)))))))))
               input-directories)))
          (replace 'check
            (lambda* (#:key tests? #:allow-other-keys)
              (when tests?
                (begin
                  (setenv "REBAR_CACHE_DIR" "/tmp")
                  (invoke "make" "-j" (number->string (parallel-job-count))
                          "tests"))))))))
    (native-inputs (list rebar3 rebar3-proper erlang-proper))
    (propagated-inputs (list erlang))
    (home-page "https://github.com/lfe/lfe")
    (synopsis "Lisp Flavoured Erlang")
    (description
     "LFE, Lisp Flavoured Erlang, is a Lisp syntax front-end to the Erlang
compiler.  Code produced with it is compatible with \"normal\" Erlang
 code.  An LFE evaluator and shell is also included.")
    (license license:asl2.0)))

(define-public erlang-hut
  (package
    (name "erlang-hut")
    (version "1.3.0")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "hut" version))
              (sha256
               (base32
                "0qxmkazkakrmvd9n1im4ad43wxgh189fqcd9lfsz58fqan2x45by"))))
    (build-system rebar-build-system)
    (home-page "https://github.com/tolbrino/hut")
    (synopsis "Helper library for making Erlang libraries logging framework
agnostic")
    (description "This package provides a helper library for making Erlang
libraries logging framework agnostic.")
    (license license:expat)))

(define-public erlang-ranch
  (package
    (name "erlang-ranch")
    (version "2.1.0")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "ranch" version))
              (sha256
               (base32
                "1ivhf5jn1bc0crgvj05fi3cavdmpcb5i9c50dyvj3kfjcmngm7w2"))))
    (build-system rebar-build-system)
    (home-page "https://github.com/ninenines/ranch")
    (synopsis "Socket acceptor pool for TCP protocols")
    (description
     "Ranch aims to provide everything you need to accept TCP
connections with a small code base and low latency while being easy to use
directly as an application or to embed into your own.")
    (license license:isc)))

(define-public erlang-setup
  (package
    (name "erlang-setup")
    (version "2.1.0")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "setup" version))
              (sha256
               (base32
                "1ibif0vnf1g16shn09jjfa13k4h9vdxgrbyajvm5py0cixbp5l7g"))))
    (build-system rebar-build-system)
    (home-page "https://github.com/uwiger/setup")
    (synopsis "Generic setup application for Erlang-based systems")
    (description
     "This utility offers a framework for initializing and
configuring a system, with a set of conventions allowing each component to
provide callbacks for different steps in the installation procedure.")
    (license license:asl2.0)))

(define-public erlang-tdiff
  (package
    (name "erlang-tdiff")
    (version "0.1.2")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "tdiff" version))
              (sha256
               (base32
                "0xbq7p9ii2kp49ms1kylj92ih2jiwvqwimb8jy4aalljz5lf3hp0"))))
    (build-system rebar-build-system)
    (home-page "https://github.com/tomas-abrahamsson/tdiff")
    (synopsis "Difference library")
    (description "This package provides an Erlang implementation of the O(ND)
difference algorithm by Eugene W. Myers.")
    (license license:lgpl2.0+)))

(define-public erlang-unite
  (package
    (name "erlang-unite")
    (version "0.3.2")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "unite" version))
              (sha256
               (base32
                "1dg2pynspba6z25bvriinrsjxal5maqzg90vzsaw2wyc3rhzr098"))))
    (build-system rebar-build-system)
    (arguments
     `(#:phases (modify-phases %standard-phases
                  (add-before 'build 'symlink-pkg-name
                    (lambda _
                      (symlink "erlang_color" "_checkouts/color") #t)))))
    (inputs (list erlang-erlang-color erlang-tdiff))
    (home-page "https://github.com/eproxus/unite")
    (synopsis "Pretty EUnit test formatters")
    (description "Pretty EUnit test formatters")
    (license license:expat)))

(define-public erlang-exometer-core
  (package
    (name "erlang-exometer-core")
    (version "1.6.1")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "exometer_core" version))
              (sha256
               (base32
                "0svdd9gzdgw80szrpf3c3xxsq9jd8mwlqn8vyra3i6zjc6lz06pc"))))
    (build-system rebar-build-system)
    (arguments
     `(#:tests? #f)) ;TODO: Tests fail
    (inputs (list erlang-folsom erlang-hut erlang-meck erlang-parse-trans
                  erlang-setup))
    (home-page "https://github.com/Feuerlabs/exometer_core")
    (synopsis "Code instrumentation and metrics collection")
    (description "Code instrumentation and metrics collection package.")
    (license license:mpl2.0)))

(define-public erlang-cowlib
  (package
    (name "erlang-cowlib")
    (version "2.11.0")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "cowlib" version))
              (sha256
               (base32
                "05c4bsyxgv01nnah2may9qc1x27pvp9pyni1byrvcv5crgy4nvng"))))
    (build-system rebar-build-system)
    (arguments
     `(#:tests? #f)) ;TODO
    (home-page "https://github.com/ninenines/cowlib")
    (synopsis "Support library for manipulating Web protocols")
    (description
     "Cowlib provides libraries for parsing and building messages
for various Web protocols, including HTTP/1.1, HTTP/2 and Websocket.  It is
optimized for completeness rather than speed. No value is ignored, they are
all returned.")
    (license license:isc)))

(define-public erlang-cowboy
  (package
    (name "erlang-cowboy")
    (version "2.9.0")
    (source (origin
              (method url-fetch)
              (uri (hexpm-uri "cowboy" version))
              (sha256
               (base32
                "1phv0a1zbgk7imfgcm0dlacm7hbjcdygb0pqmx4s26jf9f9rywic"))))
    (build-system rebar-build-system)
    (inputs (list erlang-cowlib erlang-ranch))
    (home-page "https://github.com/ninenines/cowboy")
    (synopsis "Small, fast, modern HTTP server for Erlang/OTP")
    (description
     "Cowboy aims to provide a complete HTTP stack in a small code
base.  It is optimized for low latency and low memory usage, in part because
it uses binary strings.

Cowboy provides routing capabilities, selectively dispatching requests to
handlers written in Erlang.  It can easily be embedded in any other
application.")
    (license license:isc)))
