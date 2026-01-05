# EPFL thesis/project report LaTeX template

Template for ESL-EPFL (BSc, MSc, or doctoral) theses and semester projects, adapted from the [HexHive template](https://github.com/HexHive/thesis_template) by Mathias Payer.
The template contains a rough structure with some hints for systems-oriented projects but the same structure is easily adaptable to other research projects as well.

Check out [the compiled example document](./sample.pdf) if you want to see how it is rendered.


# License and acknowledgement

The source code and LaTeX package is licensed under the LPPL. This work may be distributed and/or modified under the conditions of the LaTeX Project Public License, either version 1.3 of this license or (at your option) any later version. The latest version of this license is in http://www.latex-project.org/lppl.txt


# Prerequisites

Make sure you have the necessary LaTeX packages installed. For Ubuntu/Debian, the installation instructions are as follows:

```
sudo apt install make texlive-base texlive-bibtex-extra texlive-latex-base \
                 texlive-latex-extra texlive-latex-recommended \
                 texlive-science texlive-lang-german texlive-lang-french \
                 texlive-bibtex-extra biber rubber
```


# Editing

You will edit the files `thesis.tex` (this is where you write your report)  and `thesis.bib` (this is where you add all your references). Add figures in a `./figures` directory. To create the PDF of your thesis, run `make`.
