/// Subject glossary + fuzzy spell-fix for diagram labels.
///
/// Students (and sometimes the AI reading their handwriting) misspell labels:
/// "mitocondria", "chloroplst", "nuclues". We keep a bundled list of correct
/// NCERT-level terms and snap each label to the closest term when it is
/// "close enough".
///
/// Algorithm (easy to explain in an interview):
///   1. Normalise: lowercase, keep only letters/spaces.
///   2. Compute Damerau–Levenshtein distance (insert / delete / substitute /
///      swap two neighbouring letters) to every glossary term.
///   3. Accept the best match only if distance <= ~25% of the word length
///      (min 1, max 3). Short words therefore need an almost exact match, so
///      "ear" never becomes "eye".
///   4. Keep the user's casing style (Title Case for the output).
library;

import 'dart:math' as math;

class Glossary {
  Glossary._();

  /// Correctly spelled terms, grouped by subject (kept small & offline).
  static const Map<String, List<String>> terms = {
    'Biology': [
      'Cell wall', 'Cell membrane', 'Plasma membrane', 'Cytoplasm', 'Nucleus', 'Nucleolus',
      'Nuclear membrane', 'Chromatin', 'Mitochondria', 'Mitochondrion', 'Chloroplast',
      'Vacuole', 'Central vacuole', 'Ribosome', 'Ribosomes', 'Golgi apparatus', 'Golgi body',
      'Endoplasmic reticulum', 'Rough endoplasmic reticulum', 'Smooth endoplasmic reticulum',
      'Lysosome', 'Centrosome', 'Centriole', 'Plastid', 'Thylakoid', 'Stroma', 'Grana',
      'Xylem', 'Phloem', 'Cambium', 'Epidermis', 'Cortex', 'Pith', 'Stomata', 'Stoma',
      'Guard cell', 'Guard cells', 'Root hair', 'Root cap', 'Petal', 'Sepal', 'Stamen',
      'Anther', 'Filament', 'Pistil', 'Stigma', 'Style', 'Ovary', 'Ovule', 'Receptacle',
      'Pollen grain', 'Embryo', 'Cotyledon', 'Plumule', 'Radicle', 'Seed coat',
      'Leaf', 'Stem', 'Root', 'Midrib', 'Vein', 'Petiole', 'Lamina',
      'Heart', 'Right atrium', 'Left atrium', 'Right ventricle', 'Left ventricle', 'Aorta',
      'Pulmonary artery', 'Pulmonary vein', 'Vena cava', 'Superior vena cava',
      'Inferior vena cava', 'Valve', 'Septum', 'Artery', 'Vein', 'Capillary',
      'Brain', 'Cerebrum', 'Cerebellum', 'Medulla', 'Medulla oblongata', 'Pons',
      'Hypothalamus', 'Pituitary gland', 'Spinal cord', 'Neuron', 'Dendrite', 'Axon',
      'Cell body', 'Nerve ending', 'Synapse', 'Myelin sheath',
      'Mouth', 'Oesophagus', 'Esophagus', 'Stomach', 'Liver', 'Gall bladder', 'Pancreas',
      'Small intestine', 'Large intestine', 'Rectum', 'Anus', 'Duodenum', 'Appendix',
      'Salivary gland', 'Tongue', 'Teeth',
      'Trachea', 'Bronchus', 'Bronchi', 'Bronchiole', 'Alveoli', 'Alveolus', 'Lungs',
      'Diaphragm', 'Larynx', 'Pharynx', 'Nasal cavity', 'Ribs',
      'Kidney', 'Ureter', 'Urinary bladder', 'Urethra', 'Nephron', "Bowman's capsule",
      'Glomerulus', 'Renal artery', 'Renal vein',
      'Eye', 'Cornea', 'Iris', 'Pupil', 'Lens', 'Retina', 'Optic nerve', 'Ciliary muscle',
      'Ear', 'Ear drum', 'Cochlea', 'Pinna', 'Testis', 'Uterus', 'Fallopian tube', 'Oviduct',
      'Vas deferens', 'Seminal vesicle', 'Prostate gland', 'Amoeba', 'Pseudopodia',
      'Food vacuole', 'Contractile vacuole', 'Flagellum', 'Cilia', 'Chlorophyll',
      'Sunlight', 'Carbon dioxide', 'Oxygen', 'Water', 'Glucose',
    ],
    'Physics': [
      'Convex lens', 'Concave lens', 'Concave mirror', 'Convex mirror', 'Principal axis',
      'Principal focus', 'Focal length', 'Optical centre', 'Centre of curvature', 'Pole',
      'Incident ray', 'Reflected ray', 'Refracted ray', 'Emergent ray', 'Normal',
      'Angle of incidence', 'Angle of reflection', 'Angle of refraction', 'Prism',
      'Object', 'Image', 'Battery', 'Cell', 'Bulb', 'Switch', 'Resistor', 'Rheostat',
      'Ammeter', 'Voltmeter', 'Galvanometer', 'Fuse', 'Earth wire', 'Live wire',
      'Neutral wire', 'Magnet', 'North pole', 'South pole', 'Magnetic field lines',
      'Solenoid', 'Armature', 'Commutator', 'Brushes', 'Coil', 'Electric motor',
      'Generator', 'Spectrum', 'Retina', 'Wavelength', 'Amplitude', 'Crest', 'Trough',
    ],
    'Chemistry': [
      'Test tube', 'Beaker', 'Conical flask', 'Round bottom flask', 'Burner',
      'Bunsen burner', 'Delivery tube', 'Thermometer', 'Condenser', 'Distillation flask',
      'Funnel', 'Filter paper', 'Separating funnel', 'Tripod stand', 'Wire gauze',
      'Clamp stand', 'Electrode', 'Anode', 'Cathode', 'Electrolyte', 'Lime water',
      'Hydrogen gas', 'Oxygen gas', 'Carbon dioxide', 'Water inlet', 'Water outlet',
      'Nucleus', 'Electron', 'Proton', 'Neutron', 'Shell', 'Orbit',
    ],
    'Geography': [
      'Crust', 'Mantle', 'Outer core', 'Inner core', 'Lithosphere', 'Atmosphere',
      'Hydrosphere', 'Troposphere', 'Stratosphere', 'Mesosphere', 'Thermosphere',
      'Exosphere', 'Equator', 'Tropic of Cancer', 'Tropic of Capricorn', 'Prime meridian',
      'Latitude', 'Longitude', 'Arctic circle', 'Antarctic circle', 'Volcano', 'Crater',
      'Magma chamber', 'Lava', 'Vent', 'Evaporation', 'Condensation', 'Precipitation',
      'Run off', 'Infiltration', 'Groundwater', 'Water cycle', 'Delta', 'Meander',
      'Ox-bow lake', 'Waterfall', 'Plateau', 'Mountain', 'Valley', 'River', 'Glacier',
    ],
  };

  /// All terms (unique, case-insensitive).
  static final List<String> allTerms = () {
    final seen = <String>{};
    final out = <String>[];
    for (final list in terms.values) {
      for (final t in list) {
        if (seen.add(t.toLowerCase())) out.add(t);
      }
    }
    return out;
  }();

  /// Returns the glossary-corrected label, or the original (trimmed, nicely
  /// capitalised) if nothing is close enough. [subject] ranks that subject's
  /// terms first but all terms are searched.
  static String fix(String label, {String? subject}) {
    final match = bestMatch(label, subject: subject);
    if (match != null) return match;
    return _niceCase(label.trim());
  }

  /// Closest glossary term within the allowed edit distance, else null.
  static String? bestMatch(String label, {String? subject}) {
    final norm = normalise(label);
    if (norm.isEmpty) return null;
    final allowed = maxDistanceFor(norm.length);
    String? best;
    var bestD = 1 << 30;
    final ordered = <String>[
      if (subject != null && terms.containsKey(subject)) ...terms[subject]!,
      ...allTerms,
    ];
    for (final term in ordered) {
      final t = normalise(term);
      if ((t.length - norm.length).abs() > allowed) continue; // quick reject
      final d = damerauLevenshtein(norm, t);
      if (d < bestD) {
        bestD = d;
        best = term;
        if (d == 0) break;
      }
    }
    return bestD <= allowed ? best : null;
  }

  /// Allowed typos for a word of length [n]: ~25%, between 1 and 3.
  /// Words of 3 letters or fewer must match exactly.
  static int maxDistanceFor(int n) {
    if (n <= 3) return 0;
    return math.max(1, math.min(3, (n * 0.25).floor()));
  }

  static String normalise(String s) =>
      s.toLowerCase().replaceAll(RegExp(r"[^a-z' ]"), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _niceCase(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Optimal-string-alignment Damerau–Levenshtein distance.
  static int damerauLevenshtein(String a, String b) {
    final n = a.length, m = b.length;
    if (n == 0) return m;
    if (m == 0) return n;
    final d = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = 0; i <= n; i++) {
      d[i][0] = i;
    }
    for (var j = 0; j <= m; j++) {
      d[0][j] = j;
    }
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        var v = math.min(math.min(d[i - 1][j] + 1, d[i][j - 1] + 1), d[i - 1][j - 1] + cost);
        if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
          v = math.min(v, d[i - 2][j - 2] + 1);
        }
        d[i][j] = v;
      }
    }
    return d[n][m];
  }
}
