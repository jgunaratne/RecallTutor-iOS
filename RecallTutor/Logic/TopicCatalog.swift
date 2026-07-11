import Foundation

// Topic starter catalog — port of lib/topics.ts.
enum TopicCatalog {

    private static let elementaryTopics: [Topic] = [
        Topic(label: "Sky colors", prompt: "Why is the sky blue?"),
        Topic(label: "Fish secrets", prompt: "How do fish breathe underwater?"),
        Topic(label: "Leaf magic", prompt: "Why do leaves change color?"),
        Topic(label: "Cloud stuff", prompt: "What are clouds made of?"),
        Topic(label: "Bird flight", prompt: "How do birds fly?"),
        Topic(label: "Rainy days", prompt: "Why does it rain?"),
        Topic(label: "Rainbow wonder", prompt: "What makes a rainbow?"),
        Topic(label: "Seed surprise", prompt: "How do seeds grow into plants?"),
        Topic(label: "Season switch", prompt: "Why do we have seasons?"),
        Topic(label: "Moon rocks", prompt: "What is the moon made of?"),
        Topic(label: "Magnet magic", prompt: "How do magnets stick?"),
        Topic(label: "Happy tails", prompt: "Why do dogs wag their tails?"),
        Topic(label: "Shadow play", prompt: "What are shadows?"),
        Topic(label: "Butterfly change", prompt: "How do butterflies change?"),
        Topic(label: "Salty sea", prompt: "Why is the ocean salty?"),
        Topic(label: "Boom and flash", prompt: "What makes thunder and lightning?"),
        Topic(label: "Eye colors", prompt: "How do our eyes see colors?"),
        Topic(label: "Water power", prompt: "Why do we need to drink water?"),
        Topic(label: "Starry sky", prompt: "What are stars?"),
        Topic(label: "Dive deep", prompt: "How do submarines go underwater?"),
    ]

    private static let middleSchoolTopics: [Topic] = [
        Topic(label: "How muscles work", prompt: "How do muscles make your body move?"),
        Topic(label: "Why the sky is blue", prompt: "Why does the sky look blue during the day?"),
        Topic(label: "Fractions made easy", prompt: "Explain fractions using pizza slices and real-life examples"),
        Topic(label: "What is gravity?", prompt: "What is gravity and why do things fall down?"),
        Topic(label: "How batteries work", prompt: "How does a battery store and release energy?"),
        Topic(label: "The water cycle", prompt: "Explain the water cycle step by step"),
        Topic(label: "How the internet works", prompt: "How does a website appear on my screen when I click a link?"),
        Topic(label: "What causes earthquakes", prompt: "What causes earthquakes and how do they happen?"),
        Topic(label: "Why we need sleep", prompt: "Why do humans need to sleep every night?"),
        Topic(label: "How plants eat sunlight", prompt: "How do plants turn sunlight into food?"),
        Topic(label: "What is a black hole?", prompt: "What is a black hole and could one swallow the Earth?"),
        Topic(label: "How your brain learns", prompt: "How does your brain remember things you study?"),
        Topic(label: "DNA basics", prompt: "What is DNA and why does it make everyone look different?"),
        Topic(label: "How magnets attract", prompt: "How do magnets work and why do they stick to some metals?"),
        Topic(label: "Stars and constellations", prompt: "Why do stars look like they form shapes in the sky?"),
        Topic(label: "What makes a rainbow", prompt: "How does a rainbow form after it rains?"),
        Topic(label: "Volcanoes explained", prompt: "What makes a volcano erupt and what comes out?"),
        Topic(label: "Why ice floats", prompt: "Why does ice float on water instead of sinking?"),
        Topic(label: "Animal camouflage", prompt: "How do animals use camouflage to hide from predators?"),
        Topic(label: "Sound and vibrations", prompt: "How does sound travel from a guitar string to your ear?"),
    ]

    private static let highSchoolTopics: [Topic] = [
        Topic(label: "Grasp statistics", prompt: "Explain confidence intervals in simple terms"),
        Topic(label: "Picture the math", prompt: "What are vectors in geometry and how do they work?"),
        Topic(label: "Natural selection", prompt: "How does natural selection drive evolution over time?"),
        Topic(label: "Chemical bonding", prompt: "What is the difference between ionic and covalent bonds?"),
        Topic(label: "Supply and demand", prompt: "How do supply and demand curves determine market prices?"),
        Topic(label: "How vaccines work", prompt: "How does a vaccine train your immune system?"),
        Topic(label: "The cell cycle", prompt: "Walk me through the stages of mitosis and why cells divide"),
        Topic(label: "Electricity basics", prompt: "What are voltage, current, and resistance and how do they relate?"),
        Topic(label: "Climate vs weather", prompt: "What is the difference between climate and weather?"),
        Topic(label: "Probability traps", prompt: "Explain the Monty Hall problem and why switching is better"),
        Topic(label: "How lenses work", prompt: "How do convex and concave lenses bend light differently?"),
        Topic(label: "Atomic structure", prompt: "Explain the structure of an atom and how electrons are arranged"),
        Topic(label: "Plate tectonics", prompt: "How do tectonic plates move and what effects does this have?"),
        Topic(label: "The French Revolution", prompt: "What caused the French Revolution and what were its major phases?"),
        Topic(label: "Photosynthesis deep dive", prompt: "Walk me through the light and dark reactions of photosynthesis"),
        Topic(label: "Quadratic equations", prompt: "Why does the quadratic formula work and when do you use it?"),
        Topic(label: "Digestive system", prompt: "How does food get broken down and absorbed in the digestive system?"),
        Topic(label: "How encryption works", prompt: "How does encryption keep data safe when you browse the web?"),
        Topic(label: "Newton's three laws", prompt: "Explain Newton's three laws of motion with everyday examples"),
        Topic(label: "The Cold War", prompt: "What were the main causes and turning points of the Cold War?"),
    ]

    private static let universityTopics: [Topic] = [
        Topic(label: "B-Tree indexing", prompt: "Why do databases use B-Trees for indexing and how do they maintain balance?"),
        Topic(label: "Fourier transforms", prompt: "What is the intuition behind Fourier transforms and where are they used?"),
        Topic(label: "Game theory equilibria", prompt: "Explain Nash equilibrium and its limitations in real-world scenarios"),
        Topic(label: "CRISPR mechanics", prompt: "How does the CRISPR-Cas9 system edit genes at a molecular level?"),
        Topic(label: "Consensus protocols", prompt: "How do distributed consensus algorithms like Raft achieve fault tolerance?"),
        Topic(label: "Quantum entanglement", prompt: "What is quantum entanglement and why did Einstein call it spooky action at a distance?"),
        Topic(label: "P vs NP", prompt: "What is the P vs NP problem and why does it matter for computer science?"),
        Topic(label: "General relativity", prompt: "How does general relativity describe gravity as spacetime curvature?"),
        Topic(label: "Market microstructure", prompt: "How do order books and market makers affect price discovery?"),
        Topic(label: "Compiler design", prompt: "How does a compiler transform source code through lexing, parsing, and code generation?"),
        Topic(label: "Bayes' theorem", prompt: "Explain Bayesian inference and how prior beliefs update with new evidence"),
        Topic(label: "Neural backpropagation", prompt: "How does backpropagation compute gradients in a neural network?"),
        Topic(label: "Thermodynamics", prompt: "Explain the laws of thermodynamics and the concept of entropy"),
        Topic(label: "CAP theorem", prompt: "What is the CAP theorem and how do distributed databases navigate its trade-offs?"),
        Topic(label: "Eigenvalues explained", prompt: "What are eigenvalues and eigenvectors and why are they so important in linear algebra?"),
        Topic(label: "mRNA translation", prompt: "How does the ribosome translate mRNA into a protein chain?"),
        Topic(label: "Public key crypto", prompt: "How does RSA public-key cryptography work and why is it hard to break?"),
        Topic(label: "Lambda calculus", prompt: "What is the lambda calculus and how does it relate to functional programming?"),
        Topic(label: "Type systems", prompt: "How do type systems prevent errors and what are dependent types?"),
        Topic(label: "Mechanism design", prompt: "What is mechanism design and how does it relate to auction theory?"),
    ]

    private static let professionalTopics: [Topic] = [
        Topic(label: "Salary negotiation", prompt: "What are the best strategies for negotiating a higher salary at a new job or during a raise?"),
        Topic(label: "Resume that stands out", prompt: "How do I write a resume that gets past applicant tracking systems and impresses hiring managers?"),
        Topic(label: "Career pivoting", prompt: "How do professionals successfully pivot to a completely different career field?"),
        Topic(label: "Leadership skills", prompt: "What are the key leadership skills that separate great managers from average ones?"),
        Topic(label: "Networking effectively", prompt: "How do I build a professional network without feeling fake or transactional?"),
        Topic(label: "Interview mastery", prompt: "What are the most effective techniques for answering behavioral interview questions?"),
        Topic(label: "Remote work success", prompt: "How do I stay productive, visible, and promotable while working remotely?"),
        Topic(label: "Personal branding", prompt: "How do I build a personal brand that attracts career opportunities?"),
        Topic(label: "Managing up", prompt: "What does it mean to \"manage up\" and how do I do it effectively with my boss?"),
        Topic(label: "Work-life balance", prompt: "What are evidence-based strategies for preventing burnout while advancing your career?"),
        Topic(label: "Public speaking", prompt: "How do I become a confident public speaker and deliver compelling presentations?"),
        Topic(label: "Getting promoted", prompt: "What are the unwritten rules for getting promoted at most companies?"),
        Topic(label: "Freelancing 101", prompt: "How do I transition from full-time employment to successful freelancing?"),
        Topic(label: "Conflict resolution", prompt: "How do I handle workplace conflicts and difficult conversations professionally?"),
        Topic(label: "Executive presence", prompt: "What is executive presence and how do I develop it early in my career?"),
        Topic(label: "Side hustle strategy", prompt: "How do I start a side hustle that could eventually replace my full-time income?"),
        Topic(label: "Skill stacking", prompt: "What is skill stacking and how do I combine skills to become uniquely valuable?"),
        Topic(label: "First 90 days", prompt: "What should I focus on during my first 90 days at a new job to make the best impression?"),
        Topic(label: "Mentorship", prompt: "How do I find and cultivate mentors who can accelerate my career growth?"),
        Topic(label: "AI-proof career", prompt: "Which career skills are most resistant to AI automation and how do I develop them?"),
    ]

    private static let pools: [ReadingLevel: [Topic]] = [
        .elementary: elementaryTopics,
        .middle: middleSchoolTopics,
        .high: highSchoolTopics,
        .university: universityTopics,
    ]

    /// Pick `count` random topics from the pool for the given reading level,
    /// excluding prompts already shown. Recycles if pool runs dry.
    static func pickTopics(level: ReadingLevel, count: Int = 8, excluding exclude: Set<String> = []) -> [Topic] {
        let pool = pools[level]!
        let filtered = pool.filter { !exclude.contains($0.prompt) }
        if filtered.count < count {
            let extraNeeded = count - filtered.count
            let recycled = pool.shuffled().prefix(extraNeeded).map { $0 }
            return filtered + recycled
        }
        return filtered
            .shuffled()
            .prefix(count)
            .map { $0 }
    }

    /// Pick `count` random professional topics, excluding prompts already shown. Recycles if pool runs dry.
    static func pickProfessionalTopics(count: Int = 8, excluding exclude: Set<String> = []) -> [Topic] {
        let pool = professionalTopics
        let filtered = pool.filter { !exclude.contains($0.prompt) }
        if filtered.count < count {
            let extraNeeded = count - filtered.count
            let recycled = pool.shuffled().prefix(extraNeeded).map { $0 }
            return filtered + recycled
        }
        return filtered
            .shuffled()
            .prefix(count)
            .map { $0 }
    }
}
