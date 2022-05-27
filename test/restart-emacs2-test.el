;;; restart-emacs2-test.el --- Tests for restart-emacs2              -*- lexical-binding: t; -*-

;;; Commentary:
;;; Tests for restart-emacs2, major use case is to run from the command-line
;;; using `cask exec ert-runner' but can be run interactively as well. Do
;;; M-x `eval-buffer' RET

;;; Code:

;; For interactive testing
(unless noninteractive
  (load (expand-file-name "test-helper.el") t))

(require 'restart-emacs2)

(require 'ert)
(require 'el-mock)
;; el-mock requires this
(require 'cl)

(require 'cl-lib)

(ert-deftest restart-emacs2-test-prefix-translation ()
  (with-mock
    (stub read-string => "read string")
    (should (equal (restart-emacs2--translate-prefix-to-args '(4)) '("--debug-init")))
    (should (equal (restart-emacs2--translate-prefix-to-args '(16)) '("-Q")))
    (should (equal (restart-emacs2--translate-prefix-to-args '(64)) '("read" "string")))))

(ert-deftest restart-emacs2-test-restart-capability ()
  (with-mock
    (stub display-graphic-p => nil)
    ;; `signal' tries to use this (and fails) if `system-type' is `windows-nt',
    ;; stub it out
    (stub w32-long-file-name => "/tmp")
    (let ((system-type 'windows-nt))
      (should-error (restart-emacs2--ensure-can-restart) :type (if (version<= "24.3" emacs-version)
                                                                  'user-error
                                                                'error)))

    (let ((system-type 'ms-dos))
      (should-error (restart-emacs2--ensure-can-restart) :type (if (version<= "24.3" emacs-version)
                                                                  'user-error
                                                                'error))))

  (with-mock
    (stub display-graphic-p => t)
    (let ((system-type 'windows-nt))
      (should-not (restart-emacs2--ensure-can-restart)))

    (let ((system-type 'ms-dos))
      (should-not (restart-emacs2--ensure-can-restart)))))

(ert-deftest restart-emacs2-test-path-calculation ()
  (let ((invocation-name "emacs")
        (invocation-directory "/tmp/test/"))
    (should (string= (restart-emacs2--get-emacs-binary) "/tmp/test/emacs")))

  ;; Use runemacs.exe on Windows see #2 on Github
  (with-mock
   (stub w32-long-file-name => "/tmp")
   (stub file-exists-p => t)
   (let ((invocation-name "emacs")
         (invocation-directory "/tmp/test/")
         (system-type 'windows-nt))
     (should (string= (restart-emacs2--get-emacs-binary) "/tmp/test/runemacs.exe")))))

(ert-deftest restart-emacs2-test-gui-using-sh ()
  (with-mock
    (stub restart-emacs2--get-emacs-binary => "/tmp/bin/emacs")
    (mock (call-process "sh" nil
                        0 nil
                        "-c" "/tmp/bin/emacs --debug-init &"))
    (restart-emacs2--start-gui-using-sh '("--debug-init"))))

(ert-deftest restart-emacs2-test-gui-on-windows ()
  (with-mock
    (stub restart-emacs2--get-emacs-binary => "/tmp/bin/emacs")
    ;; w32-shell-execute expects arguments to be space separated string, see #5 on Github
    (mock (w32-shell-execute "open" "/tmp/bin/emacs" "--debug-init some-random-arg"))
    (restart-emacs2--start-gui-on-windows '("--debug-init" "some-random-arg"))))

(ert-deftest restart-emacs2-test-start-emacs-in-terminal ()
  (with-mock
    (stub restart-emacs2--get-emacs-binary => "/tmp/bin/emacs")
    (mock (suspend-emacs "fg ; /tmp/bin/emacs --debug-init -nw"))
    (restart-emacs2--start-emacs-in-terminal '("--debug-init"))))

(ert-deftest restart-emacs2-test-strategy ()
  (with-mock
    (stub display-graphic-p => nil)
    ;; `signal' tries to use this (and fails) if `system-type' is `windows-nt',
    ;; stub it out
    (stub w32-long-file-name => "/tmp")
    (mock (restart-emacs2--start-emacs-in-terminal nil) :times 5)
    (dolist (system '(gnu gnu/linux gnu/kfreebsd darwin cygwin))
      (let ((system-type system))
        (should-not (restart-emacs2--launch-other-emacs nil))))

    (dolist (system '(windows-nt ms-dos))
      (let ((system-type system))
        (should-error (restart-emacs2--launch-other-emacs nil) :type (if (version<= "24.3" emacs-version)
                                                                        'user-error
                                                                      'error)))))

  (with-mock
    (stub display-graphic-p => t)
    (mock (restart-emacs2--start-gui-using-sh nil) :times 5)
    (mock (restart-emacs2--start-gui-on-windows nil) :times 2)
    (dolist (system '(gnu gnu/linux gnu/kfreebsd darwin cygwin))
      (let ((system-type system))
        (should-not (restart-emacs2--launch-other-emacs nil))))

    (dolist (system '(windows-nt ms-dos))
      (let ((system-type system))
        (should-not (restart-emacs2--launch-other-emacs nil))))))

(ert-deftest restart-emacs2-test-restart-setup ()
  (cl-letf (((symbol-function 'save-buffers-kill-emacs)
             (lambda nil
               (should (equal (cl-position (apply-partially #'restart-emacs2--launch-other-emacs
                                                            (restart-emacs2--frame-restore-args))
                                           kill-emacs-hook
                                           :test #'equal)
                              (1- (length kill-emacs-hook)))))))

    (restart-emacs2)
    ;; Make sure that hook to restart emacs is removed after the function
    ;; restart-emacs2 exits
    (should-not (cl-find (apply-partially #'restart-emacs2--launch-other-emacs
                                          (restart-emacs2--frame-restore-args))
                         kill-emacs-hook
                         :test #'equal))))

(unless noninteractive
  (ert "^restart-emacs2-"))

(provide 'restart-emacs2-test)
;;; restart-emacs2-test.el ends here
