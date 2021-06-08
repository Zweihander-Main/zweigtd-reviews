# zweigtd-reviews

> WIP

A system for time-interval reviews using org files. Many improvements planned.

## Notes

- `org-extend-today-until` is used for all to allow for days that extend past midnight
- `org-blank-before-new-entry` will affect some datetree generation for now, alleviate some issues with:
``` emacs-lisp
(setq org-blank-before-new-entry '((heading . nil)
                                   (plain-list-item . nil))
```
- `display-buffer-alist` and `set-popup-rules!` will make it easier to actually see the review as you do it: 
``` emacs-lisp
(set-popup-rules!
  '(("^\\*Capture\\*$\\|CAPTURE-.*$"
     :size 1.00 ; Allow full screen for reviews
     :quit nil
     :select t
     :autosave ignore)))
```
- Recipe:
``` emacs-lisp
(package! zweigtd-reviews
  :recipe '(:host github :repo "Zweihander-Main/zweigtd-reviews"
            :files ("zweigtd-reviews.el" "templates")))
```


## Available for Hire

I'm available for freelance, contracts, and consulting both remotely and in the Hudson Valley, NY (USA) area. [Some more about me](https://www.zweisolutions.com/about.html) and [what I can do for you](https://www.zweisolutions.com/services.html).

Feel free to drop me a message at:

```
hi [a+] zweisolutions {●} com
```

## License

[AGPLv3](./LICENSE)

    zweigtd-reviews
    Copyright (C) 2021 Zweihänder

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published
    by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
