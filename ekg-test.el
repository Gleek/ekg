;;; ekg-test.el --- Tests for ekg  -*- lexical-binding: t; -*-

;; Copyright (c) 2022-2023  Andrew Hyatt <ahyatt@gmail.com>

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2 of the
;; License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.


;;; Commentary:

;; These tests should be run and pass before every commit.

;;; Code:
(require 'ekg)
(require 'ert)
(require 'ert-x)
(require 'org)
(require 'ekg-test-utils)

(ekg-deftest ekg-test-note-lifecycle ()
  (let ((note (ekg-note-create "Test text" 'text-mode '("tag1" "tag2"))))
    (ekg-save-note note)
    ;; We should have an ID now.
    (should (ekg-note-id note))
    (should (= 1 (length (ekg-get-notes-with-tags '("tag1")))))
    ;; Just one note, even if it has both of the tags.
    (should (= 1 (length (ekg-get-notes-with-tags '("tag1" "tag2")))))
    ;; WHen we get notes with tags, it's an AND, so it shouldn't get anything.
    (should (= 0 (length (ekg-get-notes-with-tags '("tag1" "tag2" "nonexistent")))))
    (should (equal note (car (ekg-get-notes-with-tags '("tag1")))))
    (should (ekg-has-live-tags-p (ekg-note-id note)))
    (ekg-note-trash note)
    (should-not (ekg-has-live-tags-p (ekg-note-id note)))
    (should (= 0 (length (ekg-get-notes-with-tags '("tag1" "tag2")))))))

(ekg-deftest ekg-test-tags ()
  (should-not (ekg-tags))
  ;; Make sure we trim and lowercase all tags.
  (ekg-save-note (ekg-note-create "" 'text-mode '(" a" " B ")))
  (should (equal (sort (ekg-tags) #'string<) '("a" "b")))
  (should (equal (ekg-tags-including "b") '("b")))
  (should (string= (ekg-tags-display '("a" "b")) "a b")))

(ekg-deftest ekg-test-org-link-to-id ()
  (require 'ol)
  (let* ((note (ekg-note-create "" 'text-mode '("a" "b")))
         (note-buf (ekg-edit note)))
    (unwind-protect
     (progn
       ;; Can we store a link?
       (with-current-buffer note-buf
         (org-store-link nil 1)
         (should (car org-stored-links)))
       (with-temp-buffer
         ;; Does the link look correct?
         (org-mode)
         (org-insert-last-stored-link nil)
         (should (string= (buffer-string) (format "[[ekg-note:%d][EKG note: %d]]\n" (ekg-note-id note) (ekg-note-id note))))
         ;; Does the link work?
         (goto-char 1)
         (org-open-at-point nil)
         (should (eq note-buf (current-buffer)))))
     (kill-buffer note-buf))))

(ekg-deftest ekg-test-org-link-to-tags ()
  (require 'ol)
  (ekg-save-note (ekg-note-create "" 'text-mode '("a" "b")))
  (ekg-show-notes-with-any-tags '("a" "b"))
  (let* ((tag-buf (get-buffer "*ekg tags (any): a b*")))
    (unwind-protect
        (progn
          ;; Can we store a link?
          (with-current-buffer tag-buf
            (org-store-link nil 1)
            (should (car org-stored-links)))
          (with-temp-buffer
            ;; Does the link look correct?
            (org-mode)
            (org-insert-last-stored-link nil)
            (should (string= (buffer-string) "[[ekg-tags-any:(\"a\" \"b\")][EKG page for any of the tags: a, b]]\n"))
            ;; Does the link work?
            (goto-char 1)
            (org-open-at-point nil)
            (should (eq tag-buf (current-buffer)))))
      (kill-buffer tag-buf))))

(ekg-deftest ekg-test-url-handling ()
  (ekg-capture-url "http://testurl" "A URL used for testing")
  (insert "Text added to the URL")
  (ert-simulate-command '(ekg-capture-finalize))
  (should (equal (ekg-document-titles) (list (cons "http://testurl" "A URL used for testing"))))
  (should (member "doc/a url used for testing" (ekg-tags)))
  ;; Re-capture, should edit the existing note.
  (ekg-capture-url "http://testurl" "A URL used for testing")
  (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) t)))
    (when (search-backward "http://testurl")
      (replace-match "http://testurl/v2"))
    (ert-simulate-command '(ekg-capture-finalize)))
  (should (equal (ekg-document-titles) (list (cons "http://testurl/v2" "A URL used for testing")))))

(ekg-deftest ekg-test-sort-nondestructive ()
  (mapc #'ekg-save-note
      (list (ekg-note-create "a" ekg-capture-default-mode '("tag/a"))
            (ekg-note-create "b" ekg-capture-default-mode '("tag/b"))))
  (ekg-show-notes-with-any-tags '("tag/b" "tag/a"))
  (should (string= (car (ewoc-get-hf ekg-notes-ewoc)) "tags (any): tag/a tag/b")))

(ekg-deftest ekg-test-note-roundtrip ()
  (let ((text "foo\n\tbar \"baz\" ☃"))
    (ekg-save-note (ekg-note-create text #'text-mode '("test")))
    (let ((note (car (ekg-get-notes-with-tag "test"))))
      (should (ekg-note-id note))
      (should (equal text (ekg-note-text note)))
      (should (equal 'text-mode (ekg-note-mode note))))))

(ekg-deftest ekg-test-templating ()
  (ekg-save-note (ekg-note-create "ABC" #'text-mode '("test" "template")))
  (ekg-save-note (ekg-note-create "DEF" #'text-mode '("test" "template")))
  (let ((ekg-note-add-tag-hook '(ekg-on-add-tag-insert-template)))
    (ekg-capture '("test"))
    (let ((text (substring-no-properties (buffer-string))))
      (should (string-match (rx (literal "ABC")) text))
      (should (string-match (rx (literal "DEF")) text)))))

(ekg-deftest ekg-test-get-notes-with-tags ()
  (ekg-save-note (ekg-note-create "ABC" #'text-mode '("foo" "bar")))
  (should-not (ekg-get-notes-with-tags '("foo" "none")))
  (should-not (ekg-get-notes-with-tags '("none" "foo")))
  (should (= (length (ekg-get-notes-with-tags '("bar" "foo"))) 1)))

(ekg-deftest ekg-test-extract-inlines ()
  (pcase (ekg-extract-inlines "Foo %(transclude 1) %n(transclude \"abc\") Bar")
    (`(,text . ,inlines)
     (should (equal "Foo   Bar" text))
     (should (equal
              (list
               (make-ekg-inline :pos 4 :command '(transclude 1) :type 'command)
               (make-ekg-inline :pos 5 :command '(transclude "abc") :type 'note))
              inlines)))
    (_ (ert-fail "Expected cons"))))

(ekg-deftest ekg-test-extract-and-insert-inlines ()
  (cl-loop for testcase in '("foo" "Foo %(transclude 1) %n(transclude \"abc\") Bar"
                             "Foo%(transclude 1)%(transclude 2)Bar")
           do
           (should (equal testcase
                          (let ((ex-cons (ekg-extract-inlines testcase)))
                            (ekg-insert-inlines-representation
                             (car ex-cons) (cdr ex-cons)))))))

(ekg-deftest ekg-test-transclude ()
  (let ((note1 (ekg-note-create "text1 text2" 'org-mode nil))
        (note2 (ekg-note-create "text3 text4" 'text-mode nil)))
    (ekg-save-note note1)
    (ekg-save-note note2)
    (let ((ex-cons (ekg-extract-inlines
                    (format "Foo %%(transclude-note %S 1) %%(transclude-note %S 1) Bar"
                            (ekg-note-id note1) (ekg-note-id note2)))))
      (should (string-equal "Foo text1… text3… Bar"
                            (ekg-insert-inlines-results
                             (car ex-cons) (cdr ex-cons) nil))))))

(ekg-deftest ekg-test-transclude-stability ()
  (let ((note (ekg-note-create "transcluded" 'org-mode nil)))
    (ekg-save-note note)
    (ekg-capture '("tag"))
    (let ((transclude-txt (format "12%%(transclude-note %S)34 %%(transclude-note %S)"
                                  (ekg-note-id note)
                                  (ekg-note-id note)) ))
      (insert transclude-txt)
      (ert-simulate-command '(ekg-capture-finalize))
      (let ((transcluding-note (car (ekg-get-notes-with-tag "tag"))))
        ;; First, just make sure we put the transclusion in the right place.
        (ekg-edit transcluding-note)
        (should (string-match transclude-txt (buffer-substring-no-properties (point-min) (point-max))))
        (kill-buffer)
        ;; Now, add a tag and make sure the added text in the buffer doesn't
        ;; cause the transclusion to shift.
        (setf (ekg-note-tags transcluding-note) '("tag" "newtag"))
        (ekg-edit transcluding-note)
        (should (string-match transclude-txt (buffer-substring-no-properties (point-min) (point-max))))))))

(ert-deftest ekg-test-inline-with-error ()
  (let ((target (concat "Inline: Error executing inline command "
                        "%(transclude-file \"/does/not/exist\"): ")))
    ;; We only want to compare to a certain point, since we don't want this test
    ;; to break if emacs decides to change the error message for file errors.
    (should (string-equal
             target
             (substring (ekg-insert-inlines-results
                         "Inline: "
                         (list (make-ekg-inline :pos 8 :command '(transclude-file "/does/not/exist")
                                                :type 'command))
                         nil) 0 (length target))))))

(ekg-deftest ekg-test-inline-storage ()
  (let ((id)
        (inlines (list
                  (make-ekg-inline :pos 3 :command '(transclude-file "transcluded") :type 'command)
                  (make-ekg-inline :pos 4 :command '(transclude-website "http://www.example.com")
                                   :type 'note)))
        (new-inlines (list
                      (make-ekg-inline :pos 0
                                       :command '(transclude-api-call "http://api.com" 'current-weather)
                                       :type 'command)
                      (make-ekg-inline :pos 1
                                       :command '(calc "2 ^ 10")
                                       :type 'command))))
    (let ((note (ekg-note-create "foo bar" 'text-mode nil)))
      (setf (ekg-note-inlines note) inlines)
      (ekg-save-note note)
      (setq id (ekg-note-id note)))
    (let ((note (ekg-get-note-with-id id)))
      (should (equal inlines (ekg-note-inlines note)))
      (setf (ekg-note-inlines note) new-inlines)
      (ekg-save-note note)
      (should (= 2 (length (triples-with-predicate ekg-db 'inline/command)))))
    (let ((note (ekg-get-note-with-id id)))
      (should (equal new-inlines (ekg-note-inlines note)))
      (ekg-note-delete (ekg-note-id note))
      (should (= 0 (length (triples-with-predicate ekg-db 'inline/command)))))))

(ekg-deftest ekg-test-double-transclude-note ()
  (let ((note (ekg-note-create "transclusion1" 'text-mode nil)))
    (ekg-save-note note)
    (ekg-capture '("test1"))
    (insert (format "%%(transclude-note %S)" (ekg-note-id note)))
    (ekg-capture-finalize))
  (ekg-capture '("test2"))
  (insert (format "%%(transclude-note %S)"
                  (ekg-note-id
                   (car (ekg-get-notes-with-tag "test1")))))
  (ekg-capture-finalize)
  (should (string-match-p "transclusion1"
                          (ekg-display-note-text
                           (car (ekg-get-notes-with-tag "test2"))))))

(ert-deftest ekg-test-display-note-template ()
  (let ((ekg-display-note-template
         "%n(id)%n(tagged)%n(text 100)%n(other)%n(time-tracked)")
        (note (ekg-note-create "text" 'text-mode '("tag1" "tag2"))))
    (setf (ekg-note-properties note) '(:titled/title ("Title")
                                                     :unknown/ignored "unknown"
                                                     :rendered/text "rendered"))
    (setf (ekg-note-id note) 1)
    (setf (ekg-note-modified-time note) 1682139975)
    (setf (ekg-note-creation-time note) 1682053575)
    (should (string-equal "tag1 tag2\ntext\nTitle\nCreated: 2023-04-21   Modified: 2023-04-22\n"
                          (ekg-display-note note)))))

(ert-deftest ekg-test-note-snippet ()
  (should (equal "" (ekg-note-snippet (ekg-note-create "" 'text-mode nil))))
  (should (equal "foo" (ekg-note-snippet (ekg-note-create "foo" 'text-mode nil))))
  (should (equal "foo…" (ekg-note-snippet (ekg-note-create "foo bar" 'text-mode nil) 3))))

(ekg-deftest ekg-test-overlay-interaction-growth ()
  (let ((ekg-capture-auto-tag-funcs nil))
    (ekg-capture '("test"))
    (let ((o (ekg--metadata-overlay)))
      (should (= (overlay-start o) 1))
      ;; The overlay end is the character just past the end of the visible
      ;; overlay, but still in the overlay's extent.
      (should (= (overlay-end o) (+ 1 (length "Tags: test\n"))))
      ;; Go to the end of the overlay, insert, the overlay should stay the same
      ;; - we don't allow anything to happen at the end of the overlay due to
      ;; how confusing it is.
      (goto-char (overlay-end o))
      (insert "Property: ")
      (ekg--metadata-modification o t nil nil)
      (should (= (overlay-end o) (+ 1 (length "Tags: test\n")))))))

(ekg-deftest ekg-test-overlay-interaction-resist-shrinking ()
  (let ((ekg-capture-auto-tag-funcs nil))
    (ekg-capture '("test"))
    (let ((o (ekg--metadata-overlay)))
      (should (= (overlay-end o) (+ 1 (length "Tags: test\n"))))
      ;; Go to the end of the overlay, delete the newline, it should be that you
      ;; can't really do it, the newline should regenerate itself after the
      ;; modification hook runs.
      (goto-char (overlay-end o))
      ;; When we delete, if it errors, that's OK, we don't yet have a strong
      ;; opinion on whether it should result in an error or not.
      (ignore-errors (delete-char -1))
      (should (= (overlay-end o) (+ 1 (length "Tags: test\n"))))
      (should (= (point) (overlay-end o))))))

(provide 'ekg-test)

;;; ekg-test.el ends here
