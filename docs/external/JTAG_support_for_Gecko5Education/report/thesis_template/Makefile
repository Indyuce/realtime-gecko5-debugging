name=semesterProject

all: $(name).tex $(wildcard *.bib) $(wildcard *.tex)
	rm -f $(name).pdf
	latexmk -pdf $(name).tex

clean:
	latexmk -c
	rm -f $(name).bbl $(name).bcf $(name).blg

