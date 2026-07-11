import Foundation

/// Home screen topic sections, in display order.
enum TopicCategory: String, CaseIterable {
    case science = "Science"
    case humanities = "Humanities"
    case socialScience = "Social Science"
    case business = "Business & Finance"
    case technology = "Technology"
    case careers = "Jobs & Careers"

    /// SF Symbol shown next to the section title on the home screen.
    var icon: String {
        switch self {
        case .science: "atom"
        case .humanities: "books.vertical"
        case .socialScience: "person.2"
        case .business: "chart.line.uptrend.xyaxis"
        case .technology: "cpu"
        case .careers: "briefcase"
        }
    }
}

// Topic starter catalog — port of lib/topics.ts, split into per-section pools.
// Science/Humanities/Social Science vary by reading level; Jobs & Careers is
// level-independent.
enum TopicCatalog {

    // MARK: - Science

    private static let elementaryScience: [Topic] = [
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

    private static let middleSchoolScience: [Topic] = [
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

    private static let highSchoolScience: [Topic] = [
        Topic(label: "Grasp statistics", prompt: "Explain confidence intervals in simple terms"),
        Topic(label: "Picture the math", prompt: "What are vectors in geometry and how do they work?"),
        Topic(label: "Natural selection", prompt: "How does natural selection drive evolution over time?"),
        Topic(label: "Chemical bonding", prompt: "What is the difference between ionic and covalent bonds?"),
        Topic(label: "How vaccines work", prompt: "How does a vaccine train your immune system?"),
        Topic(label: "The cell cycle", prompt: "Walk me through the stages of mitosis and why cells divide"),
        Topic(label: "Electricity basics", prompt: "What are voltage, current, and resistance and how do they relate?"),
        Topic(label: "Climate vs weather", prompt: "What is the difference between climate and weather?"),
        Topic(label: "Probability traps", prompt: "Explain the Monty Hall problem and why switching is better"),
        Topic(label: "How lenses work", prompt: "How do convex and concave lenses bend light differently?"),
        Topic(label: "Atomic structure", prompt: "Explain the structure of an atom and how electrons are arranged"),
        Topic(label: "Plate tectonics", prompt: "How do tectonic plates move and what effects does this have?"),
        Topic(label: "Photosynthesis deep dive", prompt: "Walk me through the light and dark reactions of photosynthesis"),
        Topic(label: "Quadratic equations", prompt: "Why does the quadratic formula work and when do you use it?"),
        Topic(label: "Digestive system", prompt: "How does food get broken down and absorbed in the digestive system?"),
        Topic(label: "How encryption works", prompt: "How does encryption keep data safe when you browse the web?"),
        Topic(label: "Newton's three laws", prompt: "Explain Newton's three laws of motion with everyday examples"),
    ]

    private static let universityScience: [Topic] = [
        Topic(label: "B-Tree indexing", prompt: "Why do databases use B-Trees for indexing and how do they maintain balance?"),
        Topic(label: "Fourier transforms", prompt: "What is the intuition behind Fourier transforms and where are they used?"),
        Topic(label: "CRISPR mechanics", prompt: "How does the CRISPR-Cas9 system edit genes at a molecular level?"),
        Topic(label: "Consensus protocols", prompt: "How do distributed consensus algorithms like Raft achieve fault tolerance?"),
        Topic(label: "Quantum entanglement", prompt: "What is quantum entanglement and why did Einstein call it spooky action at a distance?"),
        Topic(label: "P vs NP", prompt: "What is the P vs NP problem and why does it matter for computer science?"),
        Topic(label: "General relativity", prompt: "How does general relativity describe gravity as spacetime curvature?"),
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
    ]

    // MARK: - Humanities

    private static let elementaryHumanities: [Topic] = [
        Topic(label: "Castle life", prompt: "What was it like to live in a castle?"),
        Topic(label: "Pyramid builders", prompt: "How did people build the pyramids?"),
        Topic(label: "Cave paintings", prompt: "Why did people long ago paint on cave walls?"),
        Topic(label: "First writing", prompt: "How did people invent writing?"),
        Topic(label: "Fairy tales", prompt: "Why do we tell fairy tales?"),
        Topic(label: "Music makers", prompt: "Why do people all over the world make music?"),
        Topic(label: "Museum treasures", prompt: "What do museums keep and why?"),
        Topic(label: "Knights and armor", prompt: "What did knights really do?"),
        Topic(label: "Many languages", prompt: "Why do people speak different languages?"),
        Topic(label: "Mummy mysteries", prompt: "Why did ancient Egyptians make mummies?"),
        Topic(label: "Dragon stories", prompt: "Why do so many stories have dragons?"),
        Topic(label: "Color mixing", prompt: "How do artists mix colors to make new ones?"),
    ]

    private static let middleSchoolHumanities: [Topic] = [
        Topic(label: "Ancient Rome", prompt: "What was daily life like in ancient Rome?"),
        Topic(label: "Greek myths", prompt: "Who were the Greek gods and why did people believe in them?"),
        Topic(label: "The Silk Road", prompt: "What was the Silk Road and what traveled along it?"),
        Topic(label: "Hieroglyphics", prompt: "How did ancient Egyptians write with hieroglyphics and how did we decode them?"),
        Topic(label: "Vikings at sea", prompt: "Who were the Vikings and how far did they really travel?"),
        Topic(label: "The printing press", prompt: "How did the printing press change the world?"),
        Topic(label: "The Renaissance", prompt: "What was the Renaissance and why did art explode in Italy?"),
        Topic(label: "Great Wall of China", prompt: "Why was the Great Wall of China built?"),
        Topic(label: "Language change", prompt: "Why do languages change over time and where did English come from?"),
        Topic(label: "Shakespeare's world", prompt: "Who was Shakespeare and why are his plays still famous?"),
        Topic(label: "Medieval knights", prompt: "What was it really like to be a medieval knight?"),
        Topic(label: "World religions", prompt: "What are the world's major religions and how did they begin?"),
    ]

    private static let highSchoolHumanities: [Topic] = [
        Topic(label: "The French Revolution", prompt: "What caused the French Revolution and what were its major phases?"),
        Topic(label: "The Cold War", prompt: "What were the main causes and turning points of the Cold War?"),
        Topic(label: "Renaissance art", prompt: "How did Renaissance artists change painting forever?"),
        Topic(label: "Socrates and Plato", prompt: "What were the core ideas of Socrates and Plato and why do they still matter?"),
        Topic(label: "World War I causes", prompt: "How did World War I start and why did it become so massive?"),
        Topic(label: "Fall of Rome", prompt: "Why did the Roman Empire fall?"),
        Topic(label: "Shakespeare's tragedies", prompt: "What makes Shakespeare's tragedies like Hamlet and Macbeth so powerful?"),
        Topic(label: "The Enlightenment", prompt: "What was the Enlightenment and how did it shape modern ideas?"),
        Topic(label: "Literary devices", prompt: "How do metaphor, irony, and symbolism work in literature?"),
        Topic(label: "History of jazz", prompt: "How did jazz emerge and influence American culture?"),
        Topic(label: "Mythology's echoes", prompt: "How do ancient myths shape modern movies and books?"),
        Topic(label: "Civil Rights Movement", prompt: "What were the key events and strategies of the Civil Rights Movement?"),
    ]

    private static let universityHumanities: [Topic] = [
        Topic(label: "The hard problem", prompt: "What is the hard problem of consciousness and why does it resist explanation?"),
        Topic(label: "Kant's ethics", prompt: "What is Kant's categorical imperative and how does it differ from utilitarianism?"),
        Topic(label: "Existentialism", prompt: "What did Sartre and Camus mean by existence preceding essence and the absurd?"),
        Topic(label: "Wittgenstein's games", prompt: "What are Wittgenstein's language games and why did he change his mind about language?"),
        Topic(label: "Postmodernism", prompt: "What is postmodernism and what was it reacting against?"),
        Topic(label: "Historiography", prompt: "How do historians decide what actually happened — and can history be objective?"),
        Topic(label: "Semiotics", prompt: "How do signs and symbols create meaning according to semiotics?"),
        Topic(label: "The epic tradition", prompt: "How were oral epics like the Iliad composed and transmitted?"),
        Topic(label: "Stoicism", prompt: "What did the Stoics actually teach and what do modern versions get wrong?"),
        Topic(label: "Aesthetics", prompt: "What makes something beautiful — is beauty objective or subjective?"),
        Topic(label: "Free will debates", prompt: "What are the compatibilist and libertarian positions on free will?"),
        Topic(label: "Critical theory", prompt: "What is the Frankfurt School and what is critical theory?"),
    ]

    // MARK: - Social Science

    private static let elementarySocialScience: [Topic] = [
        Topic(label: "Money matters", prompt: "Why do we use money instead of trading things?"),
        Topic(label: "School days", prompt: "Why do kids go to school?"),
        Topic(label: "City life", prompt: "Why do people live in cities?"),
        Topic(label: "Rules everywhere", prompt: "Why do we have rules and laws?"),
        Topic(label: "Map magic", prompt: "How do maps help us find places?"),
        Topic(label: "Hello world", prompt: "How do people say hello in different countries?"),
        Topic(label: "Price tags", prompt: "How do stores decide what things cost?"),
        Topic(label: "Town leaders", prompt: "What does a mayor do?"),
        Topic(label: "Sharing is caring", prompt: "Why does sharing make us feel good?"),
        Topic(label: "Holiday time", prompt: "Why do different families celebrate different holidays?"),
        Topic(label: "Big votes", prompt: "What happens when grown-ups vote?"),
        Topic(label: "Helping hands", prompt: "Why do people work at different jobs?"),
    ]

    private static let middleSchoolSocialScience: [Topic] = [
        Topic(label: "How money works", prompt: "Where does money get its value and how do banks work?"),
        Topic(label: "Elections explained", prompt: "How do elections work and why does every vote count?"),
        Topic(label: "What is government?", prompt: "What does a government do and why do we need one?"),
        Topic(label: "Advertising tricks", prompt: "How do advertisements convince people to buy things?"),
        Topic(label: "Why countries trade", prompt: "Why do countries buy and sell things from each other?"),
        Topic(label: "Culture and customs", prompt: "What is culture and why is it different around the world?"),
        Topic(label: "How cities grow", prompt: "Why do some cities grow huge while others stay small?"),
        Topic(label: "Peer pressure", prompt: "What is peer pressure and how does it change how people act?"),
        Topic(label: "Supply and demand", prompt: "Why do prices go up when everyone wants the same thing?"),
        Topic(label: "Laws and fairness", prompt: "How are laws made and what happens when they're unfair?"),
        Topic(label: "News and media", prompt: "How does news get made and how can you tell if it's trustworthy?"),
        Topic(label: "Habits and choices", prompt: "Why do we form habits and how can we change them?"),
    ]

    private static let highSchoolSocialScience: [Topic] = [
        Topic(label: "Supply and demand", prompt: "How do supply and demand curves determine market prices?"),
        Topic(label: "Cognitive biases", prompt: "What are the most common cognitive biases and how do they trick us?"),
        Topic(label: "Inflation explained", prompt: "What causes inflation and who wins and loses from it?"),
        Topic(label: "Conformity experiments", prompt: "What did the Asch and Milgram experiments reveal about human behavior?"),
        Topic(label: "Propaganda techniques", prompt: "How does propaganda work and how can you recognize it?"),
        Topic(label: "Globalization", prompt: "What is globalization and what are its costs and benefits?"),
        Topic(label: "Political spectrum", prompt: "What do left, right, liberal, and conservative actually mean?"),
        Topic(label: "GDP and growth", prompt: "What does GDP measure and what does it miss?"),
        Topic(label: "Opportunity cost", prompt: "What is opportunity cost and how does it shape every decision?"),
        Topic(label: "Social media psychology", prompt: "How does social media hook our brains and shape behavior?"),
        Topic(label: "Memory on trial", prompt: "How reliable is eyewitness memory according to psychology research?"),
        Topic(label: "Central banks", prompt: "What does a central bank do and how does it fight inflation?"),
    ]

    private static let universitySocialScience: [Topic] = [
        Topic(label: "Game theory equilibria", prompt: "Explain Nash equilibrium and its limitations in real-world scenarios"),
        Topic(label: "Market microstructure", prompt: "How do order books and market makers affect price discovery?"),
        Topic(label: "Mechanism design", prompt: "What is mechanism design and how does it relate to auction theory?"),
        Topic(label: "Prospect theory", prompt: "How does prospect theory explain deviations from rational choice?"),
        Topic(label: "Causal inference", prompt: "How do economists identify causation with instrumental variables and natural experiments?"),
        Topic(label: "Public choice", prompt: "How does public choice theory explain government failure?"),
        Topic(label: "Comparative advantage", prompt: "Why does comparative advantage make trade beneficial even for less productive countries?"),
        Topic(label: "Monetary transmission", prompt: "How do central bank rate changes propagate through the economy?"),
        Topic(label: "Social network theory", prompt: "How do network effects and weak ties shape opportunity and influence?"),
        Topic(label: "Cultural capital", prompt: "What is Bourdieu's cultural capital and how does it reproduce inequality?"),
        Topic(label: "IR theory", prompt: "How do realism and liberalism differ in explaining international relations?"),
        Topic(label: "Median voter theorem", prompt: "What is the median voter theorem and where does it break down?"),
    ]

    // MARK: - Business & Finance

    private static let elementaryBusiness: [Topic] = [
        Topic(label: "Piggy bank power", prompt: "Why is it smart to save money?"),
        Topic(label: "Lemonade stand", prompt: "How does a lemonade stand make money?"),
        Topic(label: "What banks do", prompt: "Where does money go when you put it in a bank?"),
        Topic(label: "Making change", prompt: "How do coins and bills add up when you buy something?"),
        Topic(label: "Needs and wants", prompt: "What's the difference between things we need and things we want?"),
        Topic(label: "Store stories", prompt: "How does a store get the toys it sells?"),
        Topic(label: "Allowance adventures", prompt: "What can you learn from getting an allowance?"),
        Topic(label: "Starting small", prompt: "How do people start their own businesses?"),
        Topic(label: "Ads everywhere", prompt: "Why do companies make commercials?"),
        Topic(label: "Fair trades", prompt: "How do people decide if a trade is fair?"),
    ]

    private static let middleSchoolBusiness: [Topic] = [
        Topic(label: "Starting a business", prompt: "What does it take to start a small business?"),
        Topic(label: "How banks make money", prompt: "How do banks make money from savings and loans?"),
        Topic(label: "Interest explained", prompt: "What is interest and how does it make money grow or debt pile up?"),
        Topic(label: "The stock market", prompt: "What is the stock market and how do people buy pieces of companies?"),
        Topic(label: "Budget basics", prompt: "How do you make a budget and why does it matter?"),
        Topic(label: "Brands and logos", prompt: "Why are brands so powerful and how do they earn trust?"),
        Topic(label: "Credit cards", prompt: "How do credit cards work and what are their hidden costs?"),
        Topic(label: "Entrepreneurs", prompt: "What makes entrepreneurs succeed where others give up?"),
        Topic(label: "Taxes explained", prompt: "What are taxes and where does tax money go?"),
        Topic(label: "Supply chains", prompt: "How does a product get from a factory to your doorstep?"),
    ]

    private static let highSchoolBusiness: [Topic] = [
        Topic(label: "Compound interest", prompt: "How does compound interest make investments grow exponentially?"),
        Topic(label: "Stocks vs bonds", prompt: "What's the difference between stocks and bonds and how risky is each?"),
        Topic(label: "How startups work", prompt: "How do startups raise money from investors and what is equity?"),
        Topic(label: "Business models", prompt: "What is a business model and how do companies like Netflix and Costco differ?"),
        Topic(label: "Marketing psychology", prompt: "How does marketing use psychology to influence buying decisions?"),
        Topic(label: "Index funds", prompt: "What is an index fund and why do many investors prefer them?"),
        Topic(label: "Accounting basics", prompt: "What do income statements and balance sheets actually tell you?"),
        Topic(label: "Monopolies", prompt: "Why are monopolies considered harmful and how are they regulated?"),
        Topic(label: "Cryptocurrency", prompt: "How does cryptocurrency work and what gives it value?"),
        Topic(label: "Personal finance", prompt: "What are the fundamentals of budgeting, saving, and building credit?"),
    ]

    private static let universityBusiness: [Topic] = [
        Topic(label: "DCF valuation", prompt: "How does discounted cash flow valuation work and what are its pitfalls?"),
        Topic(label: "Options and Greeks", prompt: "How do options work and what do the Greeks measure?"),
        Topic(label: "Portfolio theory", prompt: "What is modern portfolio theory and how does diversification reduce risk?"),
        Topic(label: "Venture capital", prompt: "How do venture capital funds work, from LPs to carry to power-law returns?"),
        Topic(label: "Efficient markets", prompt: "What is the efficient market hypothesis and what anomalies challenge it?"),
        Topic(label: "Capital structure", prompt: "How do firms choose between debt and equity — what does Modigliani-Miller say?"),
        Topic(label: "Unit economics", prompt: "How do CAC, LTV, and churn determine whether a startup can scale?"),
        Topic(label: "M&A strategy", prompt: "Why do most mergers destroy value and what makes acquisitions succeed?"),
        Topic(label: "The yield curve", prompt: "What does the yield curve signal and why do inversions predict recessions?"),
        Topic(label: "Behavioral finance", prompt: "How do investor biases create bubbles and market anomalies?"),
    ]

    // MARK: - Technology

    private static let elementaryTechnology: [Topic] = [
        Topic(label: "Computer brains", prompt: "How does a computer know what to do?"),
        Topic(label: "Phone calls", prompt: "How do phones let us talk to people far away?"),
        Topic(label: "Robot helpers", prompt: "How do robots know what to do?"),
        Topic(label: "Internet magic", prompt: "How does the internet let us see faraway things?"),
        Topic(label: "Video game fun", prompt: "How do video games work?"),
        Topic(label: "Camera clicks", prompt: "How does a camera take a picture?"),
        Topic(label: "Remote control", prompt: "How does a remote control the TV without wires?"),
        Topic(label: "Typing letters", prompt: "How does typing on a keyboard put words on the screen?"),
        Topic(label: "Charging up", prompt: "How does a battery charge a phone?"),
        Topic(label: "Talking assistants", prompt: "How does a smart speaker understand what you say?"),
    ]

    private static let middleSchoolTechnology: [Topic] = [
        Topic(label: "How the internet works", prompt: "How does information travel across the internet to reach my screen?"),
        Topic(label: "What is coding?", prompt: "What is coding and how do people give instructions to computers?"),
        Topic(label: "How search engines work", prompt: "How does a search engine find the right website out of billions?"),
        Topic(label: "Smartphone sensors", prompt: "How do smartphones know which way they're facing or how fast they're moving?"),
        Topic(label: "How Wi-Fi works", prompt: "How does Wi-Fi send data through the air without wires?"),
        Topic(label: "Video game design", prompt: "How do game designers make characters move and react on screen?"),
        Topic(label: "How passwords stay safe", prompt: "How do websites keep your password safe from hackers?"),
        Topic(label: "3D printing", prompt: "How does a 3D printer turn a digital design into a real object?"),
        Topic(label: "How GPS works", prompt: "How does GPS figure out exactly where you are?"),
        Topic(label: "Social media algorithms", prompt: "How do apps decide what to show you in your feed?"),
    ]

    private static let highSchoolTechnology: [Topic] = [
        Topic(label: "How computers store data", prompt: "How do computers represent everything as 1s and 0s?"),
        Topic(label: "What is machine learning?", prompt: "What is machine learning and how is it different from regular programming?"),
        Topic(label: "How the cloud works", prompt: "What does it actually mean when data is stored \"in the cloud\"?"),
        Topic(label: "Encryption basics", prompt: "How does encryption scramble data so only the right person can read it?"),
        Topic(label: "How processors work", prompt: "What does a CPU actually do inside a computer?"),
        Topic(label: "Open source software", prompt: "What is open source software and why do companies give code away for free?"),
        Topic(label: "How apps are built", prompt: "What's the difference between how a website and a mobile app are built?"),
        Topic(label: "Net neutrality", prompt: "What is net neutrality and why is it controversial?"),
        Topic(label: "How chatbots work", prompt: "How do AI chatbots generate responses that sound human?"),
        Topic(label: "Cybersecurity basics", prompt: "What are the most common ways hackers break into systems?"),
    ]

    private static let universityTechnology: [Topic] = [
        Topic(label: "Transformer architectures", prompt: "How do transformer architectures process sequences differently from RNNs?"),
        Topic(label: "Distributed systems", prompt: "How do distributed systems maintain consistency across multiple machines?"),
        Topic(label: "How compilers optimize code", prompt: "What techniques do compilers use to optimize code without changing its behavior?"),
        Topic(label: "Public-key infrastructure", prompt: "How does public-key infrastructure establish trust across the internet?"),
        Topic(label: "Database indexing internals", prompt: "How do B-trees and hash indexes trade off lookup speed and range queries?"),
        Topic(label: "How GPUs accelerate computing", prompt: "Why are GPUs so much faster than CPUs for certain workloads?"),
        Topic(label: "Consensus algorithms", prompt: "How do algorithms like Paxos and Raft achieve agreement despite failures?"),
        Topic(label: "OS scheduling", prompt: "How does an operating system scheduler decide which process runs next?"),
        Topic(label: "Training large language models", prompt: "What happens during pretraining and fine-tuning of a large language model?"),
        Topic(label: "Zero-knowledge proofs", prompt: "How can you prove you know something without revealing what it is?"),
    ]

    // MARK: - Jobs & Careers (level-independent)

    private static let careersTopics: [Topic] = [
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

    private static let pools: [ReadingLevel: [TopicCategory: [Topic]]] = [
        .elementary: [
            .science: elementaryScience,
            .humanities: elementaryHumanities,
            .socialScience: elementarySocialScience,
            .business: elementaryBusiness,
            .technology: elementaryTechnology,
        ],
        .middle: [
            .science: middleSchoolScience,
            .humanities: middleSchoolHumanities,
            .socialScience: middleSchoolSocialScience,
            .business: middleSchoolBusiness,
            .technology: middleSchoolTechnology,
        ],
        .high: [
            .science: highSchoolScience,
            .humanities: highSchoolHumanities,
            .socialScience: highSchoolSocialScience,
            .business: highSchoolBusiness,
            .technology: highSchoolTechnology,
        ],
        .university: [
            .science: universityScience,
            .humanities: universityHumanities,
            .socialScience: universitySocialScience,
            .business: universityBusiness,
            .technology: universityTechnology,
        ],
    ]

    /// Pick `count` random topics for a section at the given reading level,
    /// excluding prompts already shown. Recycles if the pool runs dry.
    static func pickTopics(
        category: TopicCategory,
        level: ReadingLevel,
        count: Int = 5,
        excluding exclude: Set<String> = []
    ) -> [Topic] {
        let pool = category == .careers ? careersTopics : pools[level]![category]!
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
