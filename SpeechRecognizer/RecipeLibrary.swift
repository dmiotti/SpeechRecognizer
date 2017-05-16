//
//  RecipeLibrary.swift
//  SpeechRecognizer
//
//  Created by David Miotti on 16/05/2017.
//  Copyright © 2017 Wopata. All rights reserved.
//

import UIKit

struct Recipe {
    private(set) var title: String
    private(set) var description: String
    private(set) var steps: [String]

    init(title: String, description: String, steps: [String]) {
        self.title = title
        self.description = description
        self.steps = steps
    }
}

final class RecipeLibrary {
    static let shared = RecipeLibrary()
    var recipies = [Recipe]()

    init() {
        let nemsAuxFraises = Recipe(title: "Nems aux fraises", description: "Dessert facile et bon marché. Végétarien", steps: [
            "Laver les fraises sous l'eau et les équeuter.",
            "Les couper en morceaux dans un saladier et les saupoudrer de sucre.",
            "Etaler vos feuilles de brick sur un plan de travail et couper les en deux.",
            "Beurrer les feuilles de brick à l'aide d'un pinceau et déposer au centre quelques morceaux de fraises au sucre.",
            "Poser dessus une cuillère à café de crème pâtissière et rouler les feuilles de brick comme un nem.",
            "Chaque convive trempera ses nems dans le coulis de fruits rouges froid."
        ])
        recipies.append(nemsAuxFraises)

        let tagliatellesAuxChocolat = Recipe(title: "Tagliatelles au chocolat", description: "Dessert - Très facile - Bon marché - Végétarien - Sans porc", steps: [
            "Mélanger la farine et le cacao en même temps.",
            "Ajouter le sucre et la cannelle.",
            "Faire un puit au centre et y casser les eux.",
            "Bien mélanger jusqu'à l'obtention d'une pâte lisse. Si besoin, travailler la pâte directement avec les mains.",
            "Etaler la pâte au rouleau à pâtisserie. Si besoin, la passer au laminoir. La pâte doit avoir une épaisseur de 2,5 cm environ.",
            "Découper des bandes de 1 cm de large pour former les tagliatelles.",
            "Plonger les tagliatelles au chocolat dans une casserole d'eau bouillante.",
            "Laisser cuire 3 minutes.",
            "Dresser dans les assiettes, parsemer de pistaches concassées et de sucre glace avant de servir."
            ])
        recipies.append(tagliatellesAuxChocolat)

        let amourDeSaumonEnPapillote = Recipe(title: "Amour de saumon en papillote", description: "lat principal - Très facile - Moyen", steps: [
            "Préchauffer le four à 180°C (thermostat 6).",
            "Laver, essorer et ciseler l'aneth. Peler et émincer la gousse d'ail finement. Réserver.",
            "Couper les tomates cerise en deux.",
            "Emincer les champignons après les avoir nettoyés.",
            "Déposer au centre de chaque feuille de papier cuisson un pavé de saumon, ajouter les tomates et les champignons tout autour.",
            "Parsemer les pavés de saumon d'aneth et d'ail et les arroser d'un filet de jus de citron. Poivrer, saler et terminer par un filet d'huile d'olive.",
            "Fermer les papillotes et les mettre au four pendant 25 à 30 minutes."
            ])
        recipies.append(amourDeSaumonEnPapillote)
    }
}
