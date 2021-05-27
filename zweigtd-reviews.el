;;; zweigtd-reviews.el --- WIP-*-lexical-binding:t-*-

;; Copyright (C) 2021, Zweihänder <zweidev@zweihander.me>
;;
;; Author: Zweihänder
;; Keywords: org-mode
;; Homepage: https://github.com/Zweihander-Main/zweigtd-reviews
;; Version: 0.0.1

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
(require 'org-capture) ;; TODO: you sure?
(require 'org-agenda)
;; (require 'ts)
;; (require 'dash)
(require 'zweigtd-goals)
;; (require 'org-ql) ;; TODO: elsa problems

(eval-when-compile
  (defvar org-capture-templates)
  (defvar org-extend-today-until))

(defgroup zweigtd-reviews nil
  "Customization for 'zweigtd-reviews' package."
  :group 'org
  :prefix "zweigtd-reviews-")

(defvar zweigtd-reviews--current-working-date '(1 1 1900)
  "Current date being used by org-capture for generating reviews. Usually
generated by calendar-read-date ie Gregorian format.
List in (month day year) format.")

(defvar zweigtd-reviews--current-timestamp nil
  "Current timestamp in `ts' format.")
;;TODO comment more and remove old

(defvar zweigtd-reviews-non-goals-string "OTHER"
  "")

(defcustom zweigtd-reviews-quarter-ends '("March 31"
                                          "June 30"
                                          "September 30"
                                          "December 31")
  "Ordered string list of 4 quarter end dates in Month Day format. Dates are
inclusive for ranges."
  :type (list 'string 'string 'string 'string)
  :group 'zweigtd-reviews)

(defcustom zweigtd-reviews-daily-review-template
  "* Daily Review --- %<%a, %D>
** Tasks tackled:
%(zweigtd-reviews--daily-review-string)
** Thoughts:
/Did you accomplish enough today?/
- %?
/Where did you waste time?/
-"
  "Daily review template in `org-capture-templates' template format."
  :type 'string
  :group 'zweigtd-reviews)

(defcustom zweigtd-reviews-monthly-review-template
  "%(zweigtd-reviews--monthly-review-string
  (concat
    \"How are you doing relative to your plan for this goal?\n- \n\"
    \"What do you need to do this month to make sure you're on track a month from now?\n- \n\"))
* Overall
/How is your year going overall?/
-"
  "Monthly review template in `org-capture-templates' template format."
  :type 'string
  :group 'zweigtd-reviews)


(defcustom zweigtd-reviews-weekly-review-template
  "* Week %<%W, %G>
** Admin
*** Loose Input [0/3]
- [ ] Gather all scraps of paper, business cards, receipts, and
  miscellaneous paper. Include stuff on desk. Add to inbox.
- [ ] Go through journal entries for trailing week and add in any loose TODOs
- [ ] Put into inbox any new projects, action
  items, waiting-fors, someday/maybes, etc., not yet captured.
*** Empty Your Head [0/1]
- [ ] Set a timer for 5 minutes and do brainstorming or mind-mapping
*** Review Action Lists [0/1]
- [ ] Mark off completed actions in tickler/projects/next file. Review for reminders of further action
*** Process Your Notes [0/3]
- [ ] Process email inbox
- [ ] Process physical inbox
- [ ] Process inbox file
*** Review Waiting-For List [0/1]
- [ ] Review WAIT and HOLD items
*** Review Project (and Larger Outcome) Lists [0/2]
- [ ] Review Project file, making sure one current action item is there for each
- [ ] Review Goal file, making sure everything is up to date
*** Review Calendar [0/4]
- [ ] Review scheduled/logged/deadline items for last week
- [ ] Review scheduled/logged/deadline items for next week
- [ ] Review calendar for last week
- [ ] Review calendar for next week
*** Review Any Relevant Checklists [0/2]
- [ ] Review my tickler list, add newly relevant projects to projects
- [ ] Review projects list, remove irrelevant projects to tickler
*** Misc Administration [0/1]
- [ ] Get finances up to date
** Goal tracking %?
%(zweigtd-reviews--weekly-review-string
   (concat
    \"/What did you do that worked well?/\n-  \n\"
    \"/What didn't work or got in the way?/\n-  \n\"
    \"/Should you do anything differently?/\n-  \n\"
    \"/What are your priorities for the upcoming week?/\n-  \n\"))
*** Overall
/How are the goals coming along?/
-
/How do you feel about the review?/
-"
  "Weekly review template in `org-capture-templates' template format."
  :type 'string
  :group 'zweigtd-reviews)

(defun zweigtd-reviews--goal-to-todo-string (goal)
  "Return GOAL priority in the format:
priority by yyyy-mm-dd
Will return \"\" if goal is \"OTHER\"."
  (if (string= goal zweigtd-reviews-non-goals-string)
      ""
    (let ((priority (zweigtd-goals-get-prop goal :priority))
          (schedule (zweigtd-goals-get-prop goal :schedule))
          (deadline (zweigtd-goals-get-prop goal :deadline)))
      (cond (deadline (concat priority
                              " by "
                              (format-time-string "%Y-%m-%d" deadline)))
            (schedule (concat priority
                              " beginning "
                              (format-time-string "%Y-%m-%d" schedule)))
            (t priority)))))

(defun zweigtd-reviews--num-goals-completed (goal orgql-date-predicate)
  "Return number of GOAL todos completed in ORGQL-DATE-PREDICATE.
Will return non-goal todo num if goal is \"OTHER\"."
  (let ((match
         (if (string= goal zweigtd-reviews-non-goals-string)
             `(not (tags ,@(zweigtd-goals-get-goals))) ;; TODO potential bug
           `(tags ,goal))))
    (length (org-ql-query
              :from (org-agenda-files t t)
              :where `(and (closed ,@orgql-date-predicate)
                           ,match)))))

(defun zweigtd-reviews--daily-review-string ()
  "Return the daily review agenda string."
  (save-window-excursion
    (org-agenda nil "x2")
    (progn (string-trim (buffer-string)))))

(defun zweigtd-reviews--date-to-time (date)
  "Takes DATE from calendar-read-date and outputs time string digestible by
parse-time-string."
  (let ((year (calendar-extract-year date))
        (month (calendar-extract-month date))
        (day (calendar-extract-day date)))
    (concat (number-to-string day)
            " "
            (calendar-month-name month t)
            " "
            (number-to-string year))))

(defun zweigtd-reviews--weekly-review-string (questions-string)
  "Takes a string QUESTIONS-STRING and outputs a string consisting of the
agenda divided by goal."
  (let ((agenda-strings '()))
    (maphash
     (lambda (tag v)
       (let ((numkey (plist-get v 'numkey)))
         (push
          (save-window-excursion
            (org-agenda nil (concat "xw" (char-to-string numkey)))
            (progn (string-trim (buffer-string))))
          agenda-strings)))
     zweigtd-goals--hashtable)
    (push
     (save-window-excursion
       (org-agenda nil "xw0")
       (progn (string-trim (buffer-string))))
     agenda-strings)
    (setq agenda-strings (reverse agenda-strings))
    (string-join
     (mapcar
      (lambda (tag)
        (let ((agenda-string (car agenda-strings)))
          (setq agenda-strings (cdr agenda-strings))
          (concat "*** "
                  tag
                  "\n"
                  agenda-string
                  "\n*Focus:* _"
                  (zweigtd-reviews--goal-to-todo-string tag)
                  "_\n===\n"
                  questions-string)))
      (nconc (zweigtd-goals-get-goals)
             (list "OTHER"))))))

(defun zweigtd-reviews--month-to-orgql (date)
  "Takes a DATE from calendar-read-date and outputs date-time predicate
covering whole month of that DATE for use in org-ql."
  (let* ((month (calendar-extract-month date))
         (year (calendar-extract-year date))
         (from-time (zweigtd-reviews--date-to-time date))
         (last-day (calendar-last-day-of-month month year))
         (to-time (zweigtd-reviews--date-to-time (list month last-day year))))
    `(:from ,from-time :to ,to-time)))

(defun zweigtd-reviews--monthly-review-string (questions-string)
  "Takes a string QUESTIONS-STRING and outputs a string consisting of the
goals and items accomplished divided by goal."
  (string-join
   (mapcar
    (lambda (tag)
      (concat "* "
              tag
              "\n*DONE:* "
              (number-to-string (zweigtd-reviews--num-goals-completed
                                 tag
                                 (zweigtd-reviews--month-to-orgql
                                  zweigtd-reviews--current-working-date)))
              "\n*Focus:* _"
              (zweigtd-reviews--goal-to-todo-string tag)
              "_\n-----\n"
              questions-string))
    (zweigtd-goals-get-goals))))

(defun zweigtd-reviews--position-monthly-template ()
  "Will prompt for a year/month and create+goto a datetree for montly tree.
To be used in org-capture-template as the position function."
  (setq zweigtd-reviews--current-working-date (calendar-read-date t))
  (let ((marker (org-find-olp
                 (cons
                  (org-capture-expand-file zwei/org-agenda-reviews-file)
                  (list "Monthly Reviews")))))
    (set-buffer (marker-buffer marker))
    (widen)
    (goto-char marker)
    (set-marker marker nil)
    (require 'org-datetree)
    (org-datetree-find-month-create
     zweigtd-reviews--current-working-date
     'subtree-at-point)))

(defun zweigtd-reviews--generate-monthly-template ()
  "Will parse the monthly template and feed it to org-capture-fill-template.
To be used in org-capture-template as the template function."
  (org-capture-fill-template (org-file-contents
                              zweigtd-reviews-monthly-review-template)))

(defun zweigtd-reviews--prompt-day ()
  "Prompts user for day adjusted for `org-extend-today-until' and returns start/
end ts cons cell. Defaults to using yesterday."
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
  "Prompts user for ISO week (starts Mon) and returns start/end ts cons cell."
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
  "Prompts user for month and returns start/end ts cons cell."
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
  "Get the ts cons cell range of QUARTER in YEAR."
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
    (cons q-start q-end)
    ))

(defun zweigtd-reviews--prompt-quarter ()
  "Prompts user for quarter and returns start/end ts cons cell."
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
  "Prompts user for year and returns start/end ts cons cell."
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

(defun zweigtd-goals--query-interval (interval)
  "Figure out which dates user wants over INTERVAL and return . If nil, will return already queried value. See `zweigtd-reviews-goal-' TODO"
  (pcase interval
    ('day (zweigtd-reviews--prompt-day))
    ('week (zweigtd-reviews--prompt-week))
    ('month (zweigtd-reviews--prompt-month))
    ('quarter)
    ('year (zweigtd-reviews--prompt-year))
    (_ zweigtd-reviews--current-working-date)))

;; TODO figure out org-jounral start weekday
;; TODO notes on org-extend-today-until

(defun zweigtd-reviews-goal- (interval goal grouping headings num-completed priority)
  "Returns string.

INTERVAL represents the time horizon being queried and can be one of the following:
  `day'
  `week'
  `month'
  `quarter'
  `year'
  nil  -- use already queried value; for example, use value from capture template
generator function

GOAL represents the data being queried and can be one of the following:
  `all'        -- all tasks with a goal tag
  `all+nogoal' -- all tasks, even those without a goal tag
  `nogoal'     -- all tasks without a goal tag
  goal (str) -- goal string for one particular goal

GROUPING represents how the data will be grouped and can be one of the following:
  `goal'    -- data grouped by goal
  `day'     -- data grouped by day
  `week'    -- data grouped by week
  `month'   -- data grouped by month
  `quarter' -- data grouped by quarter
  `none'    -- all data is combined

HEADINGS will include the tasks/headlines closed if non-nil.

NUM-COMPLETED will include the number of tasks/headlines closed if non-nil.

PRIORITY will include the current goal(s) priority if applicable and non-nil.
 "
  ;; Set org-ql predicate based on pcase
  (let* ((queried-date (zweigtd-goals--query-interval interval))
         (org-ql-date (zweigtd-goals--date-to-orgql-predicate queried-date)))
    )
  ;; Call org-ql
  )

;;;###autoload
(defun zweigtd-reviews-init () ; TODO: change to default init
  ""
  (setq org-capture-templates
        (-uniq (-concat
                org-capture-templates
                `(("r" "Review templates")
                  ("rm" "Monthly Review"
                   entry
                   (function zweigtd-reviews--position-monthly-template)
                   (function zweigtd-reviews--generate-monthly-template)
                   :jump-to-captured t
                   :tree-type 'monthly
                   :immediate-finish nil)
                  ("rw" "Weekly Review"
                   entry
                   (file+olp+datetree ,zwei/org-agenda-reviews-file "Weekly Reviews")
                   ,zweigtd-reviews-weekly-review-template
                   :jump-to-captured t
                   :time-prompt t
                   :tree-type 'week
                   :immediate-finish nil)
                  ("rd" "Daily Review"
                   entry
                   (function (lambda ()
                               (org-journal-new-entry nil)
                               (insert "Daily Review")))
                   ,zweigtd-reviews-daily-review-template
                   :jump-to-captured t
                   :immediate-finish nil))))))

(provide 'zweigtd-reviews)

;; Local Variables:
;; coding: utf-8
;; End:

;;; zweigtd-reviews.el ends here
