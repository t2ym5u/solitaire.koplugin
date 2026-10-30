local _ = require("i18n")

-- Rules text per variant, English (through _() like every plugin's rules)
-- and French, shown by the title-bar menu's Rules entry.

return {
    klondike = {
        en = _([[
Klondike Solitaire — Rules

Move all 52 cards to the 4 foundations, one suit each, built up from Ace to King.

Tableau piles: build down in alternating colors (e.g. red 8 on black 9). A face-down card is revealed when it becomes the top of its pile. Only a King (or a run starting with one) can be placed on an empty tableau pile.

Foundations: build up in the same suit, starting from the Ace.

Tap a card to select it, then tap a destination pile or foundation to move it there. Tap the stock pile to draw new cards (or recycle the waste once the stock is empty). Double-tap a card to send it straight to its foundation.

Undo takes back the last move; Auto-complete plays every card that can go to a foundation.
]]),
        fr = [[
Solitaire Klondike — Règles

Déplacez les 52 cartes vers les 4 fondations, une par couleur, de l'As au Roi.

Colonnes : construisez en alternant les couleurs (ex. un 8 rouge sur un 9 noir). Une carte face cachée est révélée quand elle devient le sommet de sa colonne. Seul un Roi (ou une suite commençant par un Roi) peut être posé sur une colonne vide.

Fondations : construisez dans la même couleur, en partant de l'As.

Touchez une carte pour la sélectionner, puis touchez une colonne ou une fondation de destination. Touchez la pioche pour tirer de nouvelles cartes (ou recycler la défausse une fois la pioche vide). Touchez deux fois une carte pour l'envoyer directement sur sa fondation.

Annuler reprend le dernier coup ; Terminer automatiquement joue toutes les cartes qui peuvent aller sur une fondation.
]],
    },

    freecell = {
        en = _([[
FreeCell — Rules

All 52 cards are dealt face up into 8 columns. Move them all to the 4 foundations (top right), one suit each, from Ace to King.

Columns: build down in alternating colors. Any card can go on an empty column.

Free cells (top left): each holds one card, which can be played again later.

Only one card moves at a time, but a run in sequence moves as a whole when there is room to shuffle it through the free cells and empty columns: up to (free cells + 1) × 2 to the power of the empty columns.

Tap a card or a run to select it, then tap a column, a free cell or a foundation. Double-tap a card to send it to its foundation.

Deals are numbered from 1 to 32000 like Microsoft FreeCell's; "Choose deal" replays one. Almost every deal can be won (#11982 is the famous exception).
]]),
        fr = [[
FreeCell — Règles

Les 52 cartes sont distribuées face visible en 8 colonnes. Déplacez-les toutes vers les 4 fondations (en haut à droite), une par couleur, de l'As au Roi.

Colonnes : construisez en descendant et en alternant les couleurs. N'importe quelle carte peut aller sur une colonne vide.

Cellules libres (en haut à gauche) : chacune accueille une carte, rejouable plus tard.

Une seule carte bouge à la fois, mais une suite ordonnée se déplace d'un bloc quand il y a la place de la faire transiter par les cellules libres et les colonnes vides : jusqu'à (cellules libres + 1) × 2 puissance le nombre de colonnes vides.

Touchez une carte ou une suite pour la sélectionner, puis une colonne, une cellule libre ou une fondation. Touchez deux fois une carte pour l'envoyer sur sa fondation.

Les donnes sont numérotées de 1 à 32000 comme dans le FreeCell de Microsoft ; « Choisir la donne » en rejoue une. Presque toutes les donnes sont gagnables (la n° 11982 est l'exception célèbre).
]],
    },

    spider = {
        en = _([[
Spider — Rules

Two decks, in 1, 2 or 4 suits (fewer suits is easier). Build 8 complete runs from King down to Ace in one suit; a finished run leaves the table by itself.

Columns: any card can go on a card one rank higher, whatever its suit, but only a run of one suit moves as a whole. A face-down card turns over when it becomes the top of its column. Any card or run can go on an empty column.

Stock (top left, with the number of deals left): tap it, or "Deal a row", to deal one card onto every column. You can only deal when no column is empty.

Tap a card or a run to select it, then tap the destination column.
]]),
        fr = [[
Spider — Règles

Deux jeux de cartes, en 1, 2 ou 4 couleurs (moins de couleurs, c'est plus facile). Formez 8 suites complètes du Roi à l'As dans une même couleur ; une suite terminée quitte la table d'elle-même.

Colonnes : toute carte peut aller sur une carte de rang immédiatement supérieur, quelle que soit sa couleur, mais seule une suite d'une même couleur se déplace d'un bloc. Une carte face cachée se retourne quand elle devient le sommet de sa colonne. Toute carte ou suite peut aller sur une colonne vide.

Pioche (en haut à gauche, avec le nombre de donnes restantes) : touchez-la, ou « Distribuer une rangée », pour poser une carte sur chaque colonne. On ne peut distribuer que si aucune colonne n'est vide.

Touchez une carte ou une suite pour la sélectionner, puis la colonne de destination.
]],
    },

    golf = {
        en = _([[
Golf — Rules

35 cards are dealt face up in 7 columns of 5. Clear them all onto the waste pile.

Tap a column to play its top card onto the waste, if it is one rank above or below the waste card, whatever the suit (a 7 on an 8 or a 6). Kings and Aces don't connect unless "Wrap K–A" is on.

When no card fits, tap the stock to turn its next card onto the waste. The stock is not recycled: the game is lost once it is empty and no card fits.

Your score is the number of cards left in the columns (lower is better).
]]),
        fr = [[
Golf — Règles

35 cartes sont distribuées face visible en 7 colonnes de 5. Videz-les toutes sur la défausse.

Touchez une colonne pour jouer sa carte du dessus sur la défausse, si elle a un rang de plus ou de moins que la carte de la défausse, quelle que soit sa couleur (un 7 sur un 8 ou un 6). Le Roi et l'As ne se suivent pas, sauf si « Boucle R–A » est activé.

Quand aucune carte ne convient, touchez la pioche pour retourner sa carte suivante sur la défausse. La pioche n'est pas recyclée : la partie est perdue une fois la pioche vide si aucune carte ne convient.

Votre score est le nombre de cartes restant dans les colonnes (le plus bas est le meilleur).
]],
    },

    pyramid = {
        en = _([[
Pyramid — Rules

28 cards form a pyramid of 7 rows. Clear the pyramid.

Remove two cards whose ranks add up to 13 (Jack = 11, Queen = 12): tap one, then the other. A King (13) is removed on its own with a single tap. Only uncovered cards can be played; covered cards are greyed out.

Tap the stock to turn its next card onto the waste; the top waste card can be paired too. Once the stock is empty, tap it to turn the waste over again, as many times as the number of passes allows.

The game is lost when no pair, King or stock card is left to play.
]]),
        fr = [[
Pyramide — Règles

28 cartes forment une pyramide de 7 rangées. Videz la pyramide.

Retirez deux cartes dont les rangs font 13 (Valet = 11, Dame = 12) : touchez l'une, puis l'autre. Un Roi (13) se retire seul, d'une simple touche. Seules les cartes découvertes peuvent être jouées ; les cartes recouvertes sont grisées.

Touchez la pioche pour retourner sa carte suivante sur la défausse ; la carte du dessus de la défausse peut aussi former une paire. Une fois la pioche vide, touchez-la pour retourner la défausse, autant de fois que le nombre de passes le permet.

La partie est perdue quand il ne reste ni paire, ni Roi, ni carte de pioche à jouer.
]],
    },
}
