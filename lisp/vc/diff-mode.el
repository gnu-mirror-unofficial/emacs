;; Copyright (C) 1998-2019 Free Software Foundation, Inc.
(autoload 'vc-find-revision-no-save "vc")
(defcustom diff-font-lock-syntax t
  "If non-nil, diff hunk font-lock includes source language syntax highlighting.
This highlighting is the same as added by `font-lock-mode'
when corresponding source files are visited normally.
Syntax highlighting is added over diff own highlighted changes.

If t, the default, highlight syntax only in Diff buffers created by Diff
commands that compare files or by VC commands that compare revisions.
These provide all necessary context for reliable highlighting.  This value
requires support from a VC backend to find the files being compared.
For diffs against the working-tree version of a file, the highlighting is
based on the current file contents.  File-based fontification tries to
infer fontification from the compared files.

If revision-based or file-based method fails, use hunk-based method to get
fontification from hunk alone if the value is `hunk-also'.

If `hunk-only', fontification is based on hunk alone, without full source.
It tries to highlight hunks without enough context that sometimes might result
in wrong fontification.  This is the fastest option, but less reliable."
  :version "27.1"
  :type '(choice (const :tag "Don't highlight syntax" nil)
                 (const :tag "Hunk-based also" hunk-also)
                 (const :tag "Hunk-based only" hunk-only)
                 (const :tag "Highlight syntax" t)))

(defvar diff-default-directory nil
  "The default directory where the current Diff buffer was created.")
(make-variable-buffer-local 'diff-default-directory)

  "Toggle automatic diff hunk finer highlighting (Diff Auto Refine mode).
     :background "grey85")
     :background "grey75" :weight bold)
     :background "#ffeeee")
     :background "#eeffee")
  '((default :inherit diff-removed)
    (((class color) (min-colors 88))
     :foreground "#aa2222"))
  '((default :inherit diff-added)
    (((class color) (min-colors 88))
     :foreground "#22aa22"))
  '((default :inherit diff-changed)
    (((class color) (min-colors 88))
     :foreground "#aaaa22"))
  '((t nil))
    ("^\\(?:index .*\\.\\.\\|diff \\).*\n" . 'diff-header)
    ("^Binary files .* differ\n" . 'diff-file-header)
    (,#'diff--font-lock-syntax)
                        ('unified
                        ('context "^[^-+#! \\]")
                        ('normal "^[^<>#\\]")
  (remove-overlays nil nil 'diff-mode 'syntax)
          ;; Also skip lines like "\ No newline at end of file"
	  (let ((kill-chars (list (if destp ?- ?+) ?\\)))
	      (if (memq (char-after) kill-chars)
                      (vc-find-revision (expand-file-name file) revision diff-vc-backend))
     :background "#ffcccc")
     :background "#bbffbb")
      ('unified
      ('context
                               '((?+ . (left-fringe diff-fringe-add diff-indicator-added))
                                 (?- . (left-fringe diff-fringe-del diff-indicator-removed))
                                 (?! . (left-fringe diff-fringe-rep diff-indicator-changed))
;;; Syntax highlighting from font-lock

(defun diff--font-lock-syntax (max)
  "Apply source language syntax highlighting from font-lock.
Calls `diff-syntax-fontify' on every hunk found between point
and the position in MAX."
  (when diff-font-lock-syntax
    (when (get-char-property (point) 'diff--font-lock-syntax)
      (goto-char (next-single-char-property-change
                  (point) 'diff--font-lock-syntax nil max)))
    (let* ((min (point))
           (beg (or (ignore-errors (diff-beginning-of-hunk))
                    (ignore-errors (diff-hunk-next) (point))
                    max)))
      (while (< beg max)
        (let ((end
               (save-excursion (goto-char beg) (diff-end-of-hunk) (point))))
          (if (< end min) (setq beg min))
          (unless (or (< end beg)
                      (get-char-property beg 'diff--font-lock-syntax))
            (diff-syntax-fontify beg end)
            (let ((ol (make-overlay beg end)))
              (overlay-put ol 'diff--font-lock-syntax t)
              (overlay-put ol 'diff-mode 'syntax)
              (overlay-put ol 'evaporate t)
              (overlay-put ol 'modification-hooks
                           '(diff--font-lock-syntax--refresh))))
          (goto-char (max beg end))
          (setq beg (or (ignore-errors (diff-hunk-next) (point)) max))))))
  nil)

(defun diff--font-lock-syntax--refresh (ol _after _beg _end &optional _len)
  (delete-overlay ol))

(defun diff-syntax-fontify (beg end)
  "Highlight source language syntax in diff hunk between BEG and END."
  (remove-overlays beg end 'diff-mode 'syntax)
  (save-excursion
    (diff-syntax-fontify-hunk beg end t)
    (diff-syntax-fontify-hunk beg end nil)))

(defvar diff-syntax-fontify-revisions (make-hash-table :test 'equal))

(eval-when-compile (require 'subr-x)) ; for string-trim-right

(defun diff-syntax-fontify-hunk (beg end old)
  "Highlight source language syntax in diff hunk between BEG and END.
When OLD is non-nil, highlight the hunk from the old source."
  (goto-char beg)
  (let* ((hunk (buffer-substring-no-properties beg end))
         ;; Trim a trailing newline to find hunk in diff-syntax-fontify-props
         ;; in diffs that have no newline at end of diff file.
         (text (string-trim-right (or (ignore-errors (diff-hunk-text hunk (not old) nil)) "")))
	 (line (if (looking-at "\\(?:\\*\\{15\\}.*\n\\)?[-@* ]*\\([0-9,]+\\)\\([ acd+]+\\([0-9,]+\\)\\)?")
		   (if old (match-string 1)
		     (if (match-end 3) (match-string 3) (match-string 1)))))
         (line-nb (when line
                    (if (string-match "\\([0-9]+\\),\\([0-9]+\\)" line)
                        (list (string-to-number (match-string 1 line))
                              (string-to-number (match-string 2 line)))
                      (list (string-to-number line) 1)))) ; One-line diffs
         props)
    (cond
     ((and diff-vc-backend (not (eq diff-font-lock-syntax 'hunk-only)))
      (let* ((file (diff-find-file-name old t))
             (revision (and file (if (not old) (nth 1 diff-vc-revisions)
                                   (or (nth 0 diff-vc-revisions)
                                       (vc-working-revision file))))))
        (if file
            (if (not revision)
                ;; Get properties from the current working revision
                (when (and (not old) (file-exists-p file) (file-regular-p file))
                  ;; Try to reuse an existing buffer
                  (if (get-file-buffer (expand-file-name file))
                      (with-current-buffer (get-file-buffer (expand-file-name file))
                        (setq props (diff-syntax-fontify-props nil text line-nb t)))
                    ;; Get properties from the file
                    (with-temp-buffer
                      (insert-file-contents file)
                      (setq props (diff-syntax-fontify-props file text line-nb)))))
              ;; Get properties from a cached revision
              (let* ((buffer-name (format " *diff-syntax:%s.~%s~*"
                                          (expand-file-name file) revision))
                     (buffer (gethash buffer-name diff-syntax-fontify-revisions)))
                (unless (and buffer (buffer-live-p buffer))
                  (let* ((vc-buffer (ignore-errors
                                      (vc-find-revision-no-save
                                       (expand-file-name file) revision
                                       diff-vc-backend
                                       (get-buffer-create buffer-name)))))
                    (when vc-buffer
                      (setq buffer vc-buffer)
                      (puthash buffer-name buffer diff-syntax-fontify-revisions))))
                (when buffer
                  (with-current-buffer buffer
                    (setq props (diff-syntax-fontify-props file text line-nb t))))))
          ;; If file is unavailable, get properties from the hunk alone
          (setq file (car (diff-hunk-file-names old)))
          (with-temp-buffer
            (insert text)
            (setq props (diff-syntax-fontify-props file text line-nb nil t))))))
     ((and diff-default-directory (not (eq diff-font-lock-syntax 'hunk-only)))
      (let ((file (car (diff-hunk-file-names old))))
        (if (and file (file-exists-p file) (file-regular-p file))
            ;; Try to get full text from the file
            (with-temp-buffer
              (insert-file-contents file)
              (setq props (diff-syntax-fontify-props file text line-nb)))
          ;; Otherwise, get properties from the hunk alone
          (with-temp-buffer
            (insert text)
            (setq props (diff-syntax-fontify-props file text line-nb nil t))))))
     ((memq diff-font-lock-syntax '(hunk-also hunk-only))
      (let ((file (car (diff-hunk-file-names old))))
        (with-temp-buffer
          (insert text)
          (setq props (diff-syntax-fontify-props file text line-nb nil t))))))

    ;; Put properties over the hunk text
    (goto-char beg)
    (when (and props (eq (diff-hunk-style) 'unified))
      (while (< (progn (forward-line 1) (point)) end)
        (when (or (and (not old) (not (looking-at-p "[-<]")))
                  (and      old  (not (looking-at-p "[+>]"))))
          (unless (looking-at-p "\\\\") ; skip "\ No newline at end of file"
            (if (and old (not (looking-at-p "[-<]")))
                ;; Fontify context lines only from new source,
                ;; don't refontify context lines from old source.
                (pop props)
              (let ((line-props (pop props))
                    (bol (1+ (point))))
                (dolist (prop line-props)
                  (let ((ol (make-overlay (+ bol (nth 0 prop))
                                          (+ bol (nth 1 prop))
                                          nil 'front-advance nil)))
                    (overlay-put ol 'diff-mode 'syntax)
                    (overlay-put ol 'evaporate t)
                    (overlay-put ol 'face (nth 2 prop))))))))))))

(defun diff-syntax-fontify-props (file text line-nb &optional no-init hunk-only)
  "Get font-lock properties from the source code.
FILE is the name of the source file.  TEXT is the literal source text from
hunk.  LINE-NB is a pair of numbers: start line number and the number of
lines in the hunk.  NO-INIT means no initialization is needed to set major
mode.  When HUNK-ONLY is non-nil, then don't verify the existence of the
hunk text in the source file.  Otherwise, don't highlight the hunk if the
hunk text is not found in the source file."
  (unless no-init
    (buffer-disable-undo)
    (font-lock-mode -1)
    (setq buffer-file-name nil)
    (let ((enable-local-variables :safe) ;; to find `mode:'
          (buffer-file-name file))
      (set-auto-mode)
      (when (and (memq 'generic-mode-find-file-hook find-file-hook)
                 (fboundp 'generic-mode-find-file-hook))
        (generic-mode-find-file-hook))))

  (let ((font-lock-defaults (or font-lock-defaults '(nil t)))
        (inhibit-read-only t)
        props beg end)
    (goto-char (point-min))
    (if hunk-only
        (setq beg (point-min) end (point-max))
      (forward-line (1- (nth 0 line-nb)))
      ;; non-regexp looking-at to compare hunk text for verification
      (if (search-forward text (+ (point) (length text)) t)
          (setq beg (- (point) (length text)) end (point))
        (goto-char (point-min))
        (if (search-forward text nil t)
            (setq beg (- (point) (length text)) end (point)))))

    (when (and beg end)
      (goto-char beg)
      (font-lock-ensure beg end)

      (while (< (point) end)
        (let* ((bol (point))
               (eol (line-end-position))
               line-props
               (searching t)
               (from (point)) to
               (val (get-text-property from 'face)))
          (while searching
            (setq to (next-single-property-change from 'face nil eol))
            (when val (push (list (- from bol) (- to bol) val) line-props))
            (setq val (get-text-property to 'face) from to)
            (unless (< to eol) (setq searching nil)))
          (when val (push (list from eol val) line-props))
          (push (nreverse line-props) props))
        (forward-line 1)))
    (set-buffer-modified-p nil)
    (nreverse props)))

