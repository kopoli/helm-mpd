;;; helm-mpdlib.el - MPD library
;;
;; Copyright (C) 2016 Taichi Uemura
;;
;; Author: Taichi Uemura <t.uemura00@gmail.com>
;; License: GPL3
;; Time-stamp: <2016-03-20 15:51:18 tuemura>
;;
;;; Code:

(eval-when-compile (require 'cl))

(defun helm-mpdlib-received-p ()
  "Return non-nil if have received a response."
  (save-excursion
    (search-forward-regexp "^\\(OK\\|ACK\\)" nil t)))

(defun helm-mpdlib-next-response ()
  "Go to next response."
  (move-beginning-of-line 1)
  (search-forward-regexp "^\\(OK\\|ACK\\)")
  (next-logical-line)
  (move-beginning-of-line 1))

(defun helm-mpdlib-read-line ()
  "Read the current line."
  (let (begin end)
    (move-beginning-of-line 1)
    (setq begin (point))
    (move-end-of-line 1)
    (setq end (point))
    (forward-char)
    (let ((str (buffer-substring begin end)))
      (cond ((string-match "^OK" str)
             `(:ok . ,str))
            ((string-match "^ACK" str)
             `(:ack . ,str))
            ((string-match "^\\(.*\\): \\(.*\\)$" str)
             (cons (intern (match-string 1 str)) (match-string 2 str)))
            (t
             `(:error . ,(format "Invalid line: %S" str)))))))

(defun helm-mpdlib-read-response ()
  "Read response from the current line."
  (do ((end nil end)
       (data nil data)
       (status nil status)
       (message nil message))
      (end `((:status . ,status) (:data . ,(reverse data)) (:message ,message)))
    (let ((c (helm-mpdlib-read-line)))
      (case (car c)
        ((:ok :ack :error)
         (setq end t
               status (car c)
               message (cdr c)))
        (otherwise
         (setq data (cons c data)))))))

(defun helm-mpdlib-filter (callback &rest cbarg)
  "Make a filter function."
  (lexical-let ((callback callback)
                (cbarg cbarg))
    (lambda (proc text)
      (let ((buf (process-buffer proc)))
        (when buf
          (with-current-buffer buf
            (save-excursion
              (goto-char (point-max))
              (insert text))
            (when (helm-mpdlib-received-p)
              (apply callback cbarg))))))))

(defun helm-mpdlib-send (host port str callback &optional cbarg)
  "Send STR to HOST on PORT and CALLBACK with CBARG when finished.

CALLBACK is called when the response has been completely retrieved,
with the current buffer containing the response."
  (let ((proc (open-network-stream "MPD connection" (generate-new-buffer-name "*helm-mpdlib-output*")
                                   host port)))
    ;; discard the first line.
    (set-process-filter proc nil)
    (accept-process-output proc 1)

    (set-process-filter proc (apply #'helm-mpdlib-filter callback cbarg))
    (process-send-string proc str)
    proc))

(defun helm-mpdlib-make-command (command &rest args)
  (format "%s %s\n"
          command
          (mapconcat (lambda (x) (format "%s" x))
                     args " ")))

(defun helm-mpdlib-split (data separators)
  "Split DATA into objects such as songs, files and directories."
  (do ((in data (cdr in))
       (out nil out))
      ((null in) (reverse out))
    (let* ((x (car in))
           (h (car x)))
      (cond ((cl-position h separators)
             (setq out (cons (list x) out)))
            ((consp out)
             (setcar out (cons x (car out))))))))

(defun helm-mpdlib-read-objects (separators)
  "Read objects separated by SEPARATORS."
  (let ((res (helm-mpdlib-read-response)))
    (when (eq (cdr (assq :status res)) :ok)
      (helm-mpdlib-split (cdr (assq :data res)) separators))))

(provide 'helm-mpdlib)

;;; helm-mpdlib.el ends here.