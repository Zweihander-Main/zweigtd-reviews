;;; zweigtd-reviews.el --- WIP-*-lexical-binding:t-*-

;; Copyright (C) 2021, Zweihänder <zweidev@zweihander.me>
;;
;; Author: Zweihänder
;; Keywords: outlines
;; Homepage: https://github.com/Zweihander-Main/zweigtd-reviews
;; Version: 0.0.1
;; Package-Requires: ((emacs "27.2"))

;; This file is not part of GNU Emacs.

;;; License:

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as published
;; by the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU Affero General Public License for more details.
;;
;; You should have received a copy of the GNU Affero General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; WIP
;;
;;; Code:

(require 'org)
(require 'org-datetree)
(require 'org-capture)
(require 'org-agenda)
(require 'org-element)
(require 'ts)
(require 'org-ql)
(require 'dash)
(require 'zweigtd-goals)

(eval-when-compile
  (defvar org-capture-templates)
  (defvar org-extend-today-until)
  (declare-function zweigtd-goals-get-goals "zweigtd-goals" ())
  (declare-function zweigtd-goals-get-prop "zweigtd-goals" (goal prop))
  (declare-function org-journal-new-entry "org-journal" (prefix &optional time)))

(defgroup zweigtd-reviews nil
  "Customization for 'zweigtd-reviews' package."
  :group 'org
  :prefix "zweigtd-reviews-")

(defvar zweigtd-reviews--internal-plist nil
  "Internal plist for storing time data between positioning and templating.")

(defvar zweigtd-reviews-non-goals-string "OTHER"
  "Name of the heading used for tasks that are not tagged as one of the goals.")

(defcustom zweigtd-reviews-bootstrap-key ?r
  "The character code that will be used as the `org-capture' menu key.
This is used in the bootstrapped setup.
Mixing this key with other menus isn't recommended as the bootstrap function
may erase user specified customizations that start with this key."
  :type 'character
  :group 'zweigtd-reviews)

(defcustom zweigtd-reviews-file "reviews.org"
  "String of filename where reviews will be placed in the bootstrapped setup."
  :type 'string
  :group 'zweigtd-reviews)

(defcustom zweigtd-reviews-quarter-ends '("March 31"
                                          "June 30"
                                          "September 30"
                                          "December 31")
  "Ordered string list of 4 quarter end dates in Month Day format.
Dates are inclusive for ranges."
  :type '(list string string string string)
  :group 'zweigtd-reviews)

(defcustom zweigtd-reviews-olp-name '((day . "Daily Review")
                                      (week . "Weekly Reviews")
                                      (month . "Monthly Reviews")
                                      (quarter . "Quarterly Reviews")
                                      (year . "Yearly Reviews"))
  "What outline tree name should be searched for `zweigtd-reviews-genposition'.
Should be a list of 5 cons cells with each of the intervals as the CAR and the
outline tree name as the CDR."
  :type '(repeat (cons :tag "Interval Association"
                       (symbol :tag "Interval") (string :tag "Outline name")))
  :group 'zweigtd-reviews)

(defconst zweigtd-reviews--root-dir
  (file-name-directory
   (cond (load-in-progress load-file-name)
         ((and (boundp 'byte-compile-current-file) byte-compile-current-file))
         (t (buffer-file-name))))
  "Absolute path to zweigtd-reviews base dir.")

(defun zweigtd-reviews--template-path (path)
  "Expand PATH relative to `zweigtd-reviews--root-dir'.
Result is absolute path to resource."
  (expand-file-name (concat (file-name-as-directory "templates") path)
                    zweigtd-reviews--root-dir))

(defcustom zweigtd-reviews-daily-review-template
  (org-file-contents (zweigtd-reviews--template-path "daily-review.org"))
  "Daily review template in `org-capture-templates' template format.
Can also point to file ending in .org which will be used as a template.
Templates should start with top level heading."
  :type 'string
  :group 'zweigtd-reviews)

(defcustom zweigtd-reviews-weekly-review-template
  (org-file-contents (zweigtd-reviews--template-path "weekly-review.org"))
  "Weekly review template in `org-capture-templates' template format.
Can also point to file ending in .org which will be used as a template.
Templates should start with top level heading."
  :type 'string
  :group 'zweigtd-reviews)

(defcustom zweigtd-reviews-monthly-review-template
  (org-file-contents (zweigtd-reviews--template-path "monthly-review.org"))
  "Monthly review template in `org-capture-templates' template format.
Can also point to file ending in .org which will be used as a template.
Templates should start with top level heading."
  :type 'string
  :group 'zweigtd-reviews)

(defcustom zweigtd-reviews-quarterly-review-template
  (org-file-contents (zweigtd-reviews--template-path "quarterly-review.org"))
  "Quarterly review template in `org-capture-templates' template format.
Can also point to file ending in .org which will be used as a template.
Templates should start with top level heading."
  :type 'string
  :group 'zweigtd-reviews)

(defcustom zweigtd-reviews-yearly-review-template
  (org-file-contents (zweigtd-reviews--template-path "yearly-review.org"))
  "Yearly review template in `org-capture-templates' template format.
Can also point to file ending in .org which will be used as a template.
Templates should start with top level heading."
  :type 'string
  :group 'zweigtd-reviews)

(defun zweigtd-reviews--prompt-day ()
  "Prompts user for day and return start/end ts cons cell."
  (let* ((input (ts-parse-org
                 (org-read-date nil
                                nil
                                nil
                                "Select review day --"
                                (ts-internal (ts-adjust 'day -1 (ts-now))))))
         (start (ts-apply :hour org-extend-today-until
                          :minute 0
                          :second 0
                          input))
         (end (ts-apply :hour (+ 24 org-extend-today-until)
                        :minute 0
                        :second 0
                        input)))
    (cons start end)))

(defun zweigtd-reviews--prompt-week ()
  "Prompts user for ISO week (start Mon) and return start/end ts cons cell."
  (let* ((now (ts-apply :hour org-extend-today-until
                        :minute 0
                        :second 0
                        (ts-fill (ts-now)))) ; iso starts on mon, ts starts on sun (0 indexed)
         (start-of-week (ts-adjust 'day +1 ; +1 for iso
                                   (ts-adjust 'day (- (ts-dow now)) now)))
         (iter-start (ts-adjust 'day (* -7 53) start-of-week))
         (iter-end (ts-adjust 'day +7 iter-start))
         (collection '()))
    (dotimes (i 104) ; 52 before, after
      (ignore i)
      (setq iter-start iter-end)
      (setq iter-end (ts-adjust 'day +7 iter-end))
      (push (cons (concat (format "W%02d" (ts-woy iter-start))
                          ", "
                          (number-to-string (ts-year iter-start))
                          " | "
                          (ts-format "%d %b %Y - " iter-start)
                          (ts-format "%d %b %Y" (ts-adjust 'day +6 iter-start)))
                  (cons iter-start iter-end))
            collection))
    (cdr (assoc (completing-read
                 "Select which week: "
                 (reverse collection)
                 nil
                 t
                 nil
                 nil
                 (nth 52 collection)) ; Default week just before this one
                collection))))

(defun zweigtd-reviews--prompt-month ()
  "Prompts user for month and return start/end ts cons cell."
  (let* ((input-list (calendar-read-date t))
         (year (nth 2 input-list))
         (month (nth 0 input-list))
         (ts-start (ts-apply :hour org-extend-today-until
                             :minute 0
                             :second 0
                             :month month
                             :year year
                             :day 1
                             (ts-now)))
         (ts-end (ts-adjust 'month +1 ts-start)))
    (cons ts-start ts-end)))

(defun zweigtd-reviews--get-quarter-range (quarter year)
  "Get ts start/end cons of QUARTER of YEAR."
  (let* ((quarter-end-string (nth (1- quarter) zweigtd-reviews-quarter-ends))
         (quarter-start-string (nth (if (= quarter 1) 3 (- quarter 2)) zweigtd-reviews-quarter-ends))
         (q-end (ts-adjust
                 'day +1
                 (ts-apply :hour org-extend-today-until
                           :minute 0
                           :second 0
                           :year year
                           (ts-parse quarter-end-string))))
         (q-start (ts-adjust
                   'day +1
                   (ts-apply :hour org-extend-today-until
                             :minute 0
                             :second 0
                             :year (if (= quarter 1) (1- year) year)
                             (ts-parse quarter-start-string)))))
    (cons q-start q-end)))

(defun zweigtd-reviews--prompt-quarter ()
  "Prompts user for quarter and return start/end ts cons cell."
  (let* ((now (ts-apply :hour org-extend-today-until
                        :minute 0
                        :second 0
                        (ts-fill (ts-now))))
         (q-current (ceiling (/ (ts-doy now) 91.25))) ; approximation
         (q-start (cond ((= q-current 2) 4)
                        ((= q-current) 2)
                        (t (- q-current 2))))
         (year (- (ts-year (ts-now)) 2))
         (collection '())
         range)
    (dotimes (i 12) ; 2 years back, 1 year forward
      (ignore i)
      (setq q-start (if (= q-start 4) 1 (1+ q-start)))
      (when (= q-start 1) (setq year (1+ year)))
      (setq range (zweigtd-reviews--get-quarter-range q-start year))
      (push (cons (concat (format "Q%d " q-start)
                          (number-to-string year)
                          " | "
                          (ts-format "%d %b %Y - " (car range))
                          (ts-format "%d %b %Y" ; -1 as it's midnight the next day
                                     (ts-adjust 'day -1 (cdr range))))
                  range)
            collection))
    (cdr (assoc (completing-read
                 "Select which quarter: "
                 (reverse collection)
                 nil
                 t
                 nil
                 nil
                 (nth 3 collection)) ; Default quarter before this one
                collection))))

(defun zweigtd-reviews--prompt-year ()
  "Prompts user for year and return start/end ts cons cell."
  (let* ((year (calendar-read
                "Year (>0): "
                (lambda (x) (> x 1900))
                (number-to-string (calendar-extract-year
                                   (calendar-current-date)))))
         (ts-start (ts-apply :hour org-extend-today-until
                             :minute 0
                             :second 0
                             :month 1
                             :year year
                             :day 1
                             (ts-now)))
         (ts-end (ts-adjust 'year +1 ts-start)))
    (cons ts-start ts-end)))

(defun zweigtd-reviews--query-interval (interval)
  "Figure out which dates user wants over INTERVAL and return TS-CONS cell.
TS-CONS cell can be used for `zweigtd-reviews--get-tasks'.

INTERVAL represents the horizon being queried. See `zweigtd-reviews-genreview'.

Returned time will take into account `org-extend-today-until' variable."
  (let ((ts-cons
         (pcase interval
           ('day (zweigtd-reviews--prompt-day))
           ('week (zweigtd-reviews--prompt-week))
           ('month (zweigtd-reviews--prompt-month))
           ('quarter (zweigtd-reviews--prompt-quarter))
           ('year (zweigtd-reviews--prompt-year)))))
    (setq zweigtd-reviews--internal-plist
          (plist-put zweigtd-reviews--internal-plist :ts-cons ts-cons))
    ts-cons))

(defun zweigtd-reviews--get-tasks (ts-cons data-to-query)
  "Return tasks accomplished DATA-TO-QUERY over TS-CONS interval.

TS-CONS should be a cons cell with car set to the start of the date interval to
query and cdr set to the end of the date interval. The values can be anything
accepted by the `:from' and `:to' arguments fed into `org-ql' time predicates.
This includes number of days (positive to look forward, negative to look
backward), a `ts' struct (recommended), or a string parseable by
`parse-time-string'.

DATA-TO-QUERY represents the data being queried and can be one of the following:
  `only-goals' -- only tasks with a goal tag
  `everything' -- all tasks, even those without a goal tag
  `no-goals'   -- all tasks without a goal tag
  goal (str) -- goal string for one particular goal"
  (let* ((org-ql-predicate `(:from ,(car ts-cons) :to ,(cdr ts-cons)))
         (goal-match (pcase data-to-query
                       ('everything t)
                       ('only-goals `(tags ,@(zweigtd-goals-get-goals)))
                       ('no-goals `(not (tags ,@(zweigtd-goals-get-goals))))
                       (_ `(tags ,data-to-query))))
         (tasks (org-ql-query :from (org-agenda-files t t)
                              :select 'element
                              :where `(and (or (closed ,@org-ql-predicate)
                                               (clocked ,@org-ql-predicate))
                                           ,goal-match))))
    tasks))

(defun zweigtd-reviews--num-tasks (tasks)
  "Take org-element TASKS list and return number of tasks."
  ;; TODO should only be closed
  (length tasks))

(defun zweigtd-reviews--tasks-to-string (tasks)
  "Take org-element TASKS list and return string with each task on a newline."
  (let (str)
    (org-element-map tasks 'headline
      (lambda (task)
        (setq str (concat str (org-element-property :raw-value task) "\n"))))
    str))

(defun zweigtd-reviews--subdivide-interval (subdivisions ts-cons)
  "Return SUBDIVISIONS list of range TS-CONS.
Important note: will return nil if the SUBDIVISIONS is larger than the range."
  (let* ((increment (pcase subdivisions
                      ('day (cons 'day +1))
                      ('week (cons 'day +7))
                      ('month (cons 'month +1))
                      ('quarter (cons 'month +3)) ;; TODO: quarter won't use user-specified variable
                      ('year (cons 'year +1))))
         (start (car ts-cons))
         (end (cdr ts-cons))
         (prev start)
         (curr (ts-adjust (car increment) (cdr increment) prev))
         (divs '()))
    (while (ts-in start end curr)
      (push (cons prev curr) divs)
      (setq prev curr)
      (setq curr (ts-adjust (car increment) (cdr increment) curr)))
    (nreverse divs)))

;;;###autoload
(defun zweigtd-reviews-genreview (grouping &optional append num-completed priority only-goals no-task-headings interval)
  "Generate review string using GROUPING to group tasks.

GROUPING decides how the data will be grouped and can be one of the following:
  `goal'
  `day'
  `week'
  `month'
  `quarter'
  `year'
  `none'

APPEND is a string that will be appended to each grouping. For example, this can
be used to add a string after each goal group asking questions relevant to that
goal.

NUM-COMPLETED will print the amount of tasks closed per grouping below that
grouping.

PRIORITY will print the priority for a goal in that goal's grouping.

ONLY-GOALS will only collect tasks that are the user defined goals.

NO-TASK-HEADINGS will not print the actual tasks closed.

If INTERVAL isn't specified using a previous function like
`zweigtd-reviews-gentemplate' or `zweigtd-reviews-genposition', it should be
specified.
INTERVAL represents the horizon being queried and can be one of the following:
  `day'
  `week'
  `month'
  `quarter'
  `year'"
  (catch 'break
    (unless interval
      (if (plist-get zweigtd-reviews--internal-plist :interval)
          (setq interval (plist-get zweigtd-reviews--internal-plist :interval))
        (throw 'break "Interval not previously set or supplied."))))
  (let* ((ts-cons (or (plist-get zweigtd-reviews--internal-plist :ts-cons)
                      (zweigtd-reviews--query-interval interval)))
         (data-to-query (if only-goals 'only-goals 'everything))
         (task-groups
          (pcase grouping
            ('goal (mapcar
                    (lambda (goal)
                      (cons (zweigtd-reviews--get-tasks ts-cons goal)
                            goal))
                    (-concat (zweigtd-goals-get-goals)
                             (unless only-goals
                               (list zweigtd-reviews-non-goals-string)))))
            ((or 'day 'week 'month 'quarter 'year)
             (mapcar
              (lambda (ts-grouping)
                (cons (zweigtd-reviews--get-tasks ts-grouping data-to-query)
                      (ts-format (car ts-grouping))))
              (zweigtd-reviews--subdivide-interval grouping ts-cons)))
            ('none
             (list (cons (zweigtd-reviews--get-tasks ts-cons data-to-query)
                         nil)))))
         (output ""))
    (mapc
     (lambda (group)
       (let* ((tasks (car group))
              (task-headings (zweigtd-reviews--tasks-to-string tasks))
              (tasks-completed (zweigtd-reviews--num-tasks tasks))
              (heading (cdr group)))
         (when heading
           (setq output
                 (concat
                  output
                  "_"
                  (if (and (eq grouping 'goal)
                           (not (s-equals-p heading zweigtd-reviews-non-goals-string)))
                      (concat ":" heading ":")
                    heading)
                  "_\n")))
         (unless no-task-headings
           (setq output
                 (concat output task-headings)))
         (when (and num-completed tasks-completed)
           (setq output
                 (concat output
                         "*DONE:* "
                         (number-to-string tasks-completed)
                         "\n")))
         (when (and priority (not (s-equals-p heading zweigtd-reviews-non-goals-string))
                    (setq output
                          (concat output
                                  "*PRIORITY:* "
                                  (zweigtd-goals-get-prop heading :priority)
                                  "\n"))))
         (when append
           (setq output (concat output append "\n")))))
     task-groups)
    (setq zweigtd-reviews--internal-plist
          (plist-put zweigtd-reviews--internal-plist :ts-cons ts-cons))
    output))

;; TODO weird position bugs which throw monthly templates out of whack
;;;###autoload
(defun zweigtd-reviews-genposition (&optional interval file)
  "Will generate a position for the template for `org-capture'.

Confusingly, this comes AFTER `zweigtd-reviews-gentemplate'.

If INTERVAL has already been set using `zweigtd-reviews-gentemplate', there's no
need to set it here.

INTERVAL represents the horizon being queried and can be one of the following:
  `day'
  `week'
  `month'
  `quarter'
  `year'

Optional FILE is the file this will be filed to. This will default to the
journal entry for the user-selected day for INTERVAL `day' and to the
corresponding tree for the other INTERVAL values."
  (catch 'break
    (cond (interval (plist-put zweigtd-reviews--internal-plist :interval interval))
          ((plist-get zweigtd-reviews--internal-plist :interval)
           (setq interval (plist-get zweigtd-reviews--internal-plist :interval)))
          (t (throw 'break "Interval not previously set or supplied."))))
  (let* ((ts-cons (or (plist-get zweigtd-reviews--internal-plist :ts-cons)
                      (zweigtd-reviews--query-interval interval)))
         (start-ts (car ts-cons))
         (org-datetree-date `(,(ts-month start-ts)
                              ,(ts-day start-ts)
                              ,(ts-year start-ts)))
         (olp-name (cdr (-find (lambda (k)
                                 (eq (car k) interval)) zweigtd-reviews-olp-name)))
         (marker (if (or file (not (eq interval 'day)))
                     (org-find-olp ; file to reviews file or arg FILE
                      (cons
                       (org-capture-expand-file (or file zweigtd-reviews-file))
                       (list olp-name)))
                   (progn ; file to journal on user selected start date
                     (org-journal-new-entry nil (ts-internal start-ts))
                     (insert olp-name)
                     (point-marker)))))
    (set-buffer (marker-buffer marker))
    (widen)
    (goto-char marker)
    (set-marker marker nil)
    (pcase interval
      ('day (when file (org-datetree-find-date-create org-datetree-date
                                                      'subtree-at-point)))
      ('week (org-datetree-find-month-create org-datetree-date
                                             'subtree-at-point)))
    (setq zweigtd-reviews--internal-plist nil)))

;;;###autoload
(defun zweigtd-reviews-gentemplate (interval &optional template)
  "Will generate a template prefilled with the user-selected INTERVAL.

Confusingly, this comes BEFORE `zweigtd-reviews-genposition'. Therefore,
INTERVAL is mandatory as it won't have been set prior to this.

INTERVAL represents the horizon being queried and can be one of the following:
  `day'
  `week'
  `month'
  `quarter'
  `year'

TEMPLATE will correspond to the template corresponding to INTERVAL but can also
be set to a custom template."
  (unless template
    (setq template
          (pcase interval
            ('day zweigtd-reviews-daily-review-template)
            ('week zweigtd-reviews-weekly-review-template)
            ('month zweigtd-reviews-monthly-review-template)
            ('quarter zweigtd-reviews-quarterly-review-template)
            ('year zweigtd-reviews-yearly-review-template))))
  (let* ((ts-cons (zweigtd-reviews--query-interval interval))
         (org-overriding-default-time (ts-internal (car ts-cons))) ; will override org-capture
         (contents
          (if (s-ends-with-p ".org" template)
              (org-file-contents template)
            template)))
    (setq zweigtd-reviews--internal-plist
          (plist-put zweigtd-reviews--internal-plist :ts-cons ts-cons))
    (setq zweigtd-reviews--internal-plist
          (plist-put zweigtd-reviews--internal-plist :interval interval))
    (org-capture-put :default-time org-overriding-default-time)
    (org-capture-fill-template contents)))

;;;###autoload
(defun zweigtd-reviews-default-bootstrap ()
  "Use this to bootstrap `org-capture' with a default set of reviews.
Set the variable `zweigtd-reviews-bootstrap-key' to control the char key that is
used to contain all the review entries."
  ;; Delete previous bootstraps if present
  (when (and (member
              `(,(string zweigtd-reviews-bootstrap-key) "Review templates")
              org-capture-templates))
    (setq org-capture-templates
          (-filter (lambda (template)
                     (not (s-starts-with-p (string zweigtd-reviews-bootstrap-key)
                                           (car template))))
                   org-capture-templates)))
  ;; Set the review templates
  (setq org-capture-templates
        (-concat
         org-capture-templates
         `((,(string zweigtd-reviews-bootstrap-key) "Review templates")
           (,(concat (string zweigtd-reviews-bootstrap-key) "y") "Yearly Review"
            entry
            (function zweigtd-reviews-genposition)
            (function (lambda () (zweigtd-reviews-gentemplate 'year)))
            :jump-to-captured t
            :immediate-finish nil)
           (,(concat (string zweigtd-reviews-bootstrap-key) "q") "Quarterly Review"
            entry
            (function zweigtd-reviews-genposition)
            (function (lambda () (zweigtd-reviews-gentemplate 'quarter)))
            :jump-to-captured t
            :immediate-finish nil)
           (,(concat (string zweigtd-reviews-bootstrap-key) "m") "Monthly Review"
            entry
            (function zweigtd-reviews-genposition)
            (function (lambda () (zweigtd-reviews-gentemplate 'month)))
            :jump-to-captured t
            :immediate-finish nil)
           (,(concat (string zweigtd-reviews-bootstrap-key) "w") "Weekly Review"
            entry
            (function zweigtd-reviews-genposition)
            (function (lambda () (zweigtd-reviews-gentemplate 'week)))
            :jump-to-captured t
            :immediate-finish nil)
           (,(concat (string zweigtd-reviews-bootstrap-key) "d") "Daily Review"
            entry
            (function zweigtd-reviews-genposition)
            (function (lambda () (zweigtd-reviews-gentemplate 'day)))
            :jump-to-captured t
            :immediate-finish nil)))))

;; TODO allow more fine grain control over files polled to avoid the inbox problem
;; TODO pull in completed priorities
;; TODO fill in quarter for templates
;; TODO more template elements -- percentage complete, description of goal, past remarks, longest streaks, total clocked time, pomodoros?

(provide 'zweigtd-reviews)

;; Local Variables:
;; coding: utf-8
;; flycheck-disabled-checkers: 'emacs-lisp-elsa
;; End:

;;; zweigtd-reviews.el ends here
