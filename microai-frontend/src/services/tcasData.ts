// TCAS Omni AI Data Model & Multi-Exam Knowledge Base

export interface ExamCategory {
  id: string;
  code: string;
  name: string;
  nameTh: string;
  badge: string;
  color: string;
  description: string;
  totalScore: number;
  timeMinutes: number;
  subTopics: string[];
}

export interface CareerScenario {
  id: string;
  faculty: string;
  facultyNameTh: string;
  icon: string;
  color: string;
  badge: string;
  scenarioTitle: string;
  scenarioDescription: string;
  contextStory: string;
  choices: {
    id: string;
    text: string;
    description: string;
    skillsGained: {
      criticalThinking: number;
      empathy: number;
      leadership: number;
      analytical: number;
      creativity: number;
    };
    aiFeedback: string;
  }[];
}

export interface UniversityRequirement {
  id: string;
  facultyName: string;
  university: string;
  quotaRound1: string;
  mustHaveSkills: string[];
  recommendedProjects: string[];
  keyCriteria: string[];
  gpaThreshold: number;
  weightGpa: number;
  weightPortfolio: number;
  weightInterview: number;
}

export type ExamCategoryType =
  | 'TGAT1'
  | 'TGAT2'
  | 'TGAT3'
  | 'TPAT1'
  | 'TPAT2'
  | 'TPAT3'
  | 'TPAT4'
  | 'TPAT5'
  | 'A-Level-Math1'
  | 'A-Level-Math2'
  | 'A-Level-Physics'
  | 'A-Level-Chem'
  | 'A-Level-Bio'
  | 'A-Level-Eng'
  | 'A-Level-ThaiSoc'
  | 'POSN-Olympiad';

export interface MockQuestion {
  id: string;
  examType: ExamCategoryType;
  examTypeCode: string;
  examTypeNameTh: string;
  topic: string;
  subTopic: string;
  difficulty: 'Foundation' | 'Standard' | 'Advanced' | 'Hard' | 'Extreme';
  question: string;
  latexFormula?: string;
  diagramCode?: string;
  diagramType?: 'spatial' | 'graph-math' | 'graph-physics' | 'mermaid' | 'circuit';
  choices: {
    id: string;
    text: string;
    latex?: string;
    isCorrect: boolean;
    rootCauseError?: string;
    remedialConcept?: string;
  }[];
  explanation: string;
  rootCauseInsight: string;
  remedialGuide: {
    foundationTopic: string;
    reviewTimeMinutes: number;
    quickTip: string;
    keyFormula?: string;
  };
}

export interface TargetFacultyWeight {
  id: string;
  name: string;
  university: string;
  popularScoreTarget: number;
  weights: {
    subject: string;
    subjectKey: string;
    weightPercent: number;
    typicalScore: number;
    maxScore: number;
  }[];
}

// 0. All Supported Official Exams Definition
export const OFFICIAL_EXAM_CATEGORIES: ExamCategory[] = [
  {
    id: 'tgat',
    code: 'TGAT (90)',
    name: 'Thai General Aptitude Test',
    nameTh: 'ความถนัดทั่วไป (TGAT1, TGAT2, TGAT3)',
    badge: 'ข้อสอบกลาง ทปอ.',
    color: 'indigo',
    description: 'วัดทักษะการสื่อสารภาษาอังกฤษ การคิดอย่างมีเหตุผล และสมรรถนะการทำงานในอนาคต',
    totalScore: 100,
    timeMinutes: 180,
    subTopics: ['TGAT1 (91) English Communication', 'TGAT2 (92) Critical & Logical Thinking', 'TGAT3 (93) Future Workforce Competencies']
  },
  {
    id: 'tpat1',
    code: 'TPAT1 (71)',
    name: 'Medical Consortium Aptitude',
    nameTh: 'วิชาเฉพาะ กสพท (แพทย์, ทันตะ, เภสัช, สัตวแพทย์)',
    badge: 'กสพท / มหิดล-จุฬาฯ',
    color: 'emerald',
    description: 'ประเมินเชาวน์ปัญญา จริยธรรมทางการแพทย์ และทักษะการคิดเชื่อมโยงเชิงลึก',
    totalScore: 100,
    timeMinutes: 225,
    subTopics: ['Part 1 เชาวน์ปัญญา & ตรรกะ', 'Part 2 จริยธรรมทางการแพทย์', 'Part 3 ความคิดเชื่อมโยง']
  },
  {
    id: 'tpat3',
    code: 'TPAT3 (73)',
    name: 'Science & Engineering Aptitude',
    nameTh: 'ความถนัดด้านวิทยาศาสตร์ เทคโนโลยี และวิศวกรรมศาสตร์',
    badge: 'วิศวะ & วิทยาศาสตร์',
    color: 'blue',
    description: 'วัดการประยุกต์ฟิสิกส์ การมองมิติสัมพันธ์ 3 มิติ เชิงกลศาสตร์ และตรรกะเชิงวิทยาศาสตร์',
    totalScore: 100,
    timeMinutes: 180,
    subTopics: ['การประยุกต์ความรู้ฟิสิกส์/กลศาสตร์', 'มิติสัมพันธ์และรูปคลี่ 3 มิติ (Spatial Net)', 'การคิดเชิงวิทยาศาสตร์และเทคโนโลยี']
  },
  {
    id: 'tpat4',
    code: 'TPAT4 (74)',
    name: 'Architectural Aptitude',
    nameTh: 'ความถนัดทางสถาปัตยกรรม',
    badge: 'สถาปัตย์ & ออกแบบ',
    color: 'amber',
    description: 'วัดการมองภาพ Isometric, Perspective, การฉายแสงเงา และสัดส่วนทางสถาปัตย์',
    totalScore: 100,
    timeMinutes: 180,
    subTopics: ['Isometric & Orthographic Projection', 'Perspective & Shadow Analysis', 'Architectural Spatial Logic']
  },
  {
    id: 'alevel-math1',
    code: 'A-Level (61)',
    name: 'Applied Mathematics 1',
    nameTh: 'คณิตศาสตร์ประยุกต์ 1 (วิทย์-คณิต)',
    badge: 'A-Level สทศ./ทปอ.',
    color: 'purple',
    description: 'แคลคูลัส, เรขาคณิตวิเคราะห์, เวกเตอร์, เมทริกซ์, ตรีโกณมิติ และสถิติความน่าจะเป็น',
    totalScore: 100,
    timeMinutes: 90,
    subTopics: ['แคลคูลัส & เส้นสัมผัสกราฟ', 'ฟังก์ชันพหุนาม & พาราโบลา', 'ตรีโกณมิติ & เวกเตอร์', 'ลำดับและอนุกรม']
  },
  {
    id: 'alevel-physics',
    code: 'A-Level (64)',
    name: 'Applied Physics',
    nameTh: 'ฟิสิกส์ประยุกต์',
    badge: 'A-Level สทศ./ทปอ.',
    color: 'cyan',
    description: 'กลศาสตร์, การเคลื่อนที่แบบโปรเจกไทล์, กราฟการเคลื่อนที่ s-t/v-t, คลื่น, แสง และไฟฟ้า',
    totalScore: 100,
    timeMinutes: 90,
    subTopics: ['กลศาสตร์และการเคลื่อนที่แนวตรง (s-t, v-t, a-t)', 'การเคลื่อนที่โปรเจกไทล์ & ฮาร์มอนิก', 'คลื่นและเสียง', 'ไฟฟ้าและแม่เหล็ก']
  },
  {
    id: 'alevel-chem-bio',
    code: 'A-Level (65/66)',
    name: 'Chemistry & Biology',
    nameTh: 'เคมี & ชีววิทยาประยุกต์',
    badge: 'A-Level สทศ./ทปอ.',
    color: 'rose',
    description: 'สมดุลเคมี, กรด-เบส, ปริมาณสารสัมพันธ์, พันธุศาสตร์, และสรีรวิทยาของสิ่งมีชีวิต',
    totalScore: 100,
    timeMinutes: 90,
    subTopics: ['สมดุลเคมีและไฟฟ้าเคมี', 'ปริมาณสารสัมพันธ์และแก๊ส', 'พันธุศาสตร์และระดับโมเลกุล', 'ระบบร่างกายและพืช']
  },
  {
    id: 'posn-olympiad',
    code: 'POSN (สอวน.)',
    name: 'POSN Academic Olympiad',
    nameTh: 'คัดเลือกโอลิมปิกวิชาการ สอวน. ค่าย 1 & 2',
    badge: 'มูลนิธิ สอวน.',
    color: 'yellow',
    description: 'โจทย์ระดับการแข่งขันโอลิมปิกวิชาการ คณิตศาสตร์ ฟิสิกส์ คอมพิวเตอร์ และเคมี',
    totalScore: 100,
    timeMinutes: 180,
    subTopics: ['สอวน. ฟิสิกส์กลศาสตร์ชั้นสูง', 'สอวน. เรขาคณิตและทฤษฎีจำนวน', 'สอวน. คอมพิวเตอร์และอัลกอริทึม']
  }
];

// 1. Career & Faculty Simulation Scenarios
export const CAREER_SCENARIOS: CareerScenario[] = [
  {
    id: 'med-er-crisis',
    faculty: 'Medicine',
    facultyNameTh: 'คณะแพทยศาสตร์',
    icon: 'Stethoscope',
    color: 'emerald',
    badge: 'เวรดึกห้องฉุกเฉิน (ER Night Shift)',
    scenarioTitle: 'คนไข้วิกฤตกับเตียง ICU ที่เหลือเพียง 1 เตียง',
    scenarioDescription: 'ทดสอบทักษะการตัดสินใจภายใต้ภาวะกดดันสูง และจริยธรรมทางการแพทย์',
    contextStory: 'เวลา 02:45 น. คุณเป็นแพทย์เวรดึก มีคนไข้ 2 รายเข้ามาพร้อมกัน: รายแรกคือคุณลุงวัย 68 ปี ภาวะหัวใจวายเฉียบพลัน และรายที่สองคือเด็กวัยรุ่นอายุ 19 ปี ประสบอุบัติเหตุเลือดออกในสมองอย่างรุนแรง แต่เตียง ICU และเครื่องช่วยหายใจขั้นสูงเหลือเพียง 1 เครื่องเท่านั้น คุณจะบริหารสถานการณ์นี้อย่างไร?',
    choices: [
      {
        id: 'med-1',
        text: 'ส่งวัยรุ่นเข้า ICU ทันทีเพราะมีโอกาสรอดและอายุขัยยืนยาวกว่าตามสถิติ',
        description: 'เน้นเกณฑ์ Utility Maximization & Life-years Saved',
        skillsGained: { criticalThinking: 4, empathy: 2, leadership: 3, analytical: 5, creativity: 2 },
        aiFeedback: 'คุณมีวิธีคิดแบบนักวางแผนระบบสาธารณสุขและแพทย์ฉุกเฉินชั้นยอด (Triage Protocol) ที่ยึดหลักเกณฑ์ความคุ้มค่าทางการแพทย์ แต่ในทางปฏิบัติจำเป็นต้องมีแผนสำรองเพื่อยื้อชีวิตผู้ป่วยรายแรกด้วย Bag-Valve Mask ระหว่างส่งต่อ'
      },
      {
        id: 'med-2',
        text: 'ประเมิน Glasgow Coma Scale และ Vital Signs เชิงลึกแบบคู่ขนาน พร้อมประสานส่งต่อ รพ. เครือข่ายใกล้เคียงทันที',
        description: 'เน้นการสื่อสาร การบริหารทรัพยากร และรักษาชีวิตทั้งสองคน',
        skillsGained: { criticalThinking: 5, empathy: 4, leadership: 5, analytical: 4, creativity: 4 },
        aiFeedback: 'ยอดเยี่ยมมาก! คุณมีคุณสมบัติของ "แพทย์ผู้นำ (Physician Leader)" ที่ไม่จำกัดกรอบความคิดแค่ทรัพยากรในห้อง แต่แก้ปัญหาด้วยการประสานงานและคิดรอบด้าน เหมาะกับสายแพทย์ศาสตร์หรือเวชศาสตร์ฉุกเฉินอย่างยิ่ง'
      },
      {
        id: 'med-3',
        text: 'ปรึกษาแพทย์เฉพาะทางอาวุโส และชี้แจงญาติทั้งสองฝ่ายอย่างโปร่งใสตามหลักจริยธรรม',
        description: 'เน้นการสื่อสารเชิงเห็นอกเห็นใจและความรับผิดชอบทางกฎหมาย',
        skillsGained: { criticalThinking: 3, empathy: 5, leadership: 3, analytical: 3, creativity: 3 },
        aiFeedback: 'คุณมีความโดดเด่นด้าน Empathy และ Medical Ethics สูงมาก เหมาะสำหรับแพทย์สาขาอายุรศาสตร์ กุมารเวช หรือจิตเวชศาสตร์ ที่ต้องการการสื่อสารและเยียวยาจิตใจผู้ป่วย'
      }
    ]
  },
  {
    id: 'eng-bridge-collapse',
    faculty: 'Engineering',
    facultyNameTh: 'คณะวิศวกรรมศาสตร์',
    icon: 'Cpu',
    color: 'blue',
    badge: 'วิกฤตโครงสร้างสะพานแขวนข้ามอ่าว',
    scenarioTitle: 'เซ็นเซอร์ตรวจจับการสั่นสะเทือนระดับ Resonance ผิดปกติ',
    scenarioDescription: 'ทดสอบการคิดเชิงวิเคราะห์โครงสร้าง ฟิสิกส์ประยุกต์ และการตัดสินใจเชิงวิศวกรรม',
    contextStory: 'คุณเป็นหัวหน้าทีมวิศวกรควบคุมสะพานแขวนมูลค่าหมื่นล้าน เกิดพายุลมแรงระดับ 80 km/h ทำให้เซ็นเซอร์จับได้ว่าสะพานเริ่มเกิดการแกว่งแบบฮาร์มอนิก (Aeroelastic Flutter) คล้ายกับเหตุการณ์สะพาน Tacoma Narrows คุณต้องสั่งการก่อนสะพานพังถล่มใน 15 นาที',
    choices: [
      {
        id: 'eng-1',
        text: 'สั่งปิดการจราจร 100% ทันที พร้อมสั่งปรับ Tuned Mass Damper ในเสาตอม่อแบบ Overdrive',
        description: 'เน้น Safety-First และการควบคุมระบบไดนามิกส์',
        skillsGained: { criticalThinking: 5, empathy: 2, leadership: 5, analytical: 5, creativity: 3 },
        aiFeedback: 'คุณมีสัญชาตญาณวิศวกรโครงสร้างที่เด็ดขาด ยึดความปลอดภัยสาธารณะ (Public Safety) เป็นอันดับหนึ่ง เหมาะกับวิศวกรรมโยธา, เครื่องกล และอากาศยาน'
      },
      {
        id: 'eng-2',
        text: 'รัน Simulation จำลองค่า Finite Element Analysis (FEA) แบบเรียลไทม์เพื่อหาจุดตัดความเค้นวิกฤต',
        description: 'เน้น Data-Driven และ Computational Engineering',
        skillsGained: { criticalThinking: 4, empathy: 1, leadership: 2, analytical: 5, creativity: 4 },
        aiFeedback: 'คุณเป็นสาย Data-Driven Deep Tech ชอบแก้ปัญหาด้วยแบบจำลองตัวเลข เหมาะกับวิศวกรรมคอมพิวเตอร์, AI Data Science หรือวิศวกรรมการคำนวณขั้นสูง'
      },
      {
        id: 'eng-3',
        text: 'เปลี่ยนองศาแผงกั้นลมและลดความเร็วลมปะทะด้วยระบบควบคุมบานพับอากาศพลศาสตร์',
        description: 'เน้นนวัตกรรมและการประยุกต์ใช้วิศวกรรมควบคุมเชิงรุก',
        skillsGained: { criticalThinking: 4, empathy: 2, leadership: 4, analytical: 4, creativity: 5 },
        aiFeedback: 'คุณมีความคิดสร้างสรรค์เชิงนวัตกรรมสูง มองเห็นวิธีแก้ปัญหาที่ต้นตอของแรงลม เหมาะกับวิศวกรรมหุ่นยนต์ Mechatronics หรือ Innovation Design'
      }
    ]
  },
  {
    id: 'bba-crisis-turnaround',
    faculty: 'Business',
    facultyNameTh: 'คณะพาณิชยศาสตร์และการบัญชี / บริหารธุรกิจ',
    icon: 'TrendingUp',
    color: 'purple',
    badge: 'วิกฤตกระแสเงินสดสตาร์ตอัปยูนิคอร์น',
    scenarioTitle: 'เงินสดหมุนเวียนเหลือ 45 วัน กับต้นทุน Server AI ที่พุ่ง 400%',
    scenarioDescription: 'ทดสอบทักษะ Financial Modeling, Strategic Pivoting และการบริหารวิกฤต',
    contextStory: 'บริษัทสตาร์ตอัป AI ของคุณมีผู้ใช้งานเติบโต 10 เท่าใน 1 เดือน แต่ค่าเช่า GPU Cloud พุ่งสูงจนเงินสดสำรองจะหมดใน 45 วัน ขณะที่นักลงทุน Series B เลื่อนการโอนเงินออกไป 3 เดือนเนื่องจากสภาวะเศรษฐกิจถดถอย คุณจะแก้เกมนี้อย่างไร?',
    choices: [
      {
        id: 'bba-1',
        text: 'เปิดตัวโมเดล Premium Subscription แบบรายปีลด 40% ล่วงหน้าเพื่อระดมกระแสเงินสดทันที (Cash Injection)',
        description: 'เน้นการสร้างรายได้ด่วนและการประเมิน Customer Lifetime Value',
        skillsGained: { criticalThinking: 4, empathy: 3, leadership: 4, analytical: 5, creativity: 4 },
        aiFeedback: 'คุณมีความเฉียบคมด้าน Growth Marketing และ Corporate Finance ในการดึงเงินสดล่วงหน้า (Unearned Revenue) เข้ามาพยุง Runway โดยไม่ต้องยอมเจือจางหุ้น'
      },
      {
        id: 'bba-2',
        text: 'ทำ Quantization ลดขนาดโมเดลลงสู่ Edge Computing 0.8B เพื่อลดต้นทุนคลาวด์ 85% ทันที',
        description: 'เน้น Unit Economics และ Cost Optimization เชิงเทคโนโลยี',
        skillsGained: { criticalThinking: 5, empathy: 2, leadership: 3, analytical: 5, creativity: 5 },
        aiFeedback: 'ยอดเยี่ยม! คุณเข้าใจการปรับลด Gross Burn Rate ผ่านการ Optimize ด้านเทคโนโลยี ทำให้บริษัทกลายเป็น Lean Organization ที่ยั่งยืน'
      },
      {
        id: 'bba-3',
        text: 'เจรจาขอ Strategic Bridge Loan หรือแปลงหนี้เป็นทุนกับ Cloud Provider เพื่อยืดระยะเวลาชำระเงิน',
        description: 'เน้นทักษะการต่อรองและ Strategic Partnership',
        skillsGained: { criticalThinking: 4, empathy: 4, leadership: 5, analytical: 3, creativity: 3 },
        aiFeedback: 'คุณมีทักษะการเจรจาต่อรองแบบ C-Level ระดับโลก เหมาะกับการบริหารเชิงกลยุทธ์, การเงินองค์กร (IB) หรือ Consult'
      }
    ]
  }
];

// 2. University Portfolio Requirements
export const UNIVERSITY_REQUIREMENTS: UniversityRequirement[] = [
  {
    id: 'cu-eng-round1',
    facultyName: 'วิศวกรรมศาสตร์',
    university: 'จุฬาลงกรณ์มหาวิทยาลัย (รอบ 1 Portfolio)',
    quotaRound1: 'โครงการคัดเลือกนักเรียนที่มีความสามารถพิเศษด้านคณิต/วิทย์/โอลิมปิก',
    gpaThreshold: 3.50,
    weightGpa: 20,
    weightPortfolio: 50,
    weightInterview: 30,
    mustHaveSkills: [
      'ทักษะการเขียนโปรแกรม / Computational Thinking (Python, C++, IoT)',
      'โครงงานวิทยาศาสตร์หรือนวัตกรรมที่มีผลงานทดลองเป็นรูปธรรม',
      'ผลการแข่งขันทางวิชาการ (สอวน., TSO, Hackathon, หรือโครงงานระดับจังหวัด/ประเทศ)'
    ],
    recommendedProjects: [
      'สร้างระบบ IoT หรือ AI ตรวจจับของเสีย/ประหยัดพลังงานในชุมชน',
      'โครงงานพัฒนาฮาร์ดแวร์/ซอฟต์แวร์ที่แก้ปัญหาในโรงเรียนจริง พร้อมเก็บ Metrics'
    ],
    keyCriteria: ['ความเป็นผู้นำในโครงงาน', 'ความเข้าใจลึกซึ้งในโครงสร้างวิศวกรรม', 'Passion และความสม่ำเสมอของผลงาน 3 ปีย้อนหลัง']
  },
  {
    id: 'md-rama-round1',
    facultyName: 'แพทยศาสตร์โรงพยาบาลรามาธิบดี',
    university: 'มหาวิทยาลัยมหิดล (รอบ 1 Portfolio)',
    quotaRound1: 'โครงการแพทย์นักประดิษฐ์และนวัตกรรม / วิทยาการข้อมูลการแพทย์',
    gpaThreshold: 3.50,
    weightGpa: 15,
    weightPortfolio: 55,
    weightInterview: 30,
    mustHaveSkills: [
      'จิตสาธารณะและกิจกรรมบริการสังคมต่อเนื่องอย่างน้อย 50-100 ชั่วโมง',
      'งานวิจัยหรือนวัตกรรมสุขภาพ (Health Tech / Biomedical Concept)',
      'คะแนนสอบภาษาอังกฤษสากล (IELTS >= 6.5 หรือ TOEFL iBT >= 79)'
    ],
    recommendedProjects: [
      'ร่วมจัดทำโครงการเผยแพร่ความรู้สุขอนามัยชุมชน หรือจิตอาสาในโรงพยาบาล',
      'โครงงานวิทยาศาสตร์สุขภาพ/ชีวเคมีที่ผ่านการประกวดระดับภูมิภาค'
    ],
    keyCriteria: ['Empathy และทัศนคติต่อวิชาชีพแพทย์', 'ความสามารถในการทำงานร่วมกับผู้อื่น', 'ความซื่อสัตย์และจริยธรรม']
  },
  {
    id: 'tu-bba-round1',
    facultyName: 'พาณิชยศาสตร์และการบัญชี (BBA/หลักสูตรไทย)',
    university: 'มหาวิทยาลัยธรรมศาสตร์ (รอบ 1)',
    quotaRound1: 'โครงการนักเรียนผู้มีทักษะความเป็นเลิศทางธุรกิจและการเป็นผู้นำ',
    gpaThreshold: 3.25,
    weightGpa: 20,
    weightPortfolio: 45,
    weightInterview: 35,
    mustHaveSkills: [
      'ประสบการณ์เป็นผู้นำองค์กรนักเรียน/ประธานชมรม/สภานักเรียน',
      'ผลงานแข่งขันแผนธุรกิจ (Business Plan / Case Competition / Start-up Pitch)',
      'การจัดกิจกรรมสร้างรายได้หรือบริหารงบประมาณจริง'
    ],
    recommendedProjects: [
      'ทำ Social Enterprise หรือธุรกิจขนาดเล็กที่มียอดขายและการทำบัญชีกำไรขาดทุนจริง',
      'จัดตั้งชมรมการเงินการลงทุนในโรงเรียน'
    ],
    keyCriteria: ['ความเป็นผู้นำและความกล้าตัดสินใจ', 'ทักษะการสื่อสารโน้มน้าวใจ (Presentation)', 'Financial Literacy']
  }
];

// 3. Multi-Exam Mock Questions with Comprehensive Diagnostics & Formula Explanations
export const MOCK_QUESTIONS: MockQuestion[] = [
  // --- A-Level Physics Kinematics Graph ---
  {
    id: 'q-phys-graph-1',
    examType: 'A-Level-Physics',
    examTypeCode: '64',
    examTypeNameTh: 'A-Level ฟิสิกส์ประยุกต์',
    topic: 'กลศาสตร์ & กราฟการเคลื่อนที่แนวตรง (v-t Graph Analysis)',
    subTopic: 'การอินทิเกรตพื้นที่ใต้กราฟและความชัน',
    difficulty: 'Standard',
    question: 'วัตถุมวล 2 kg เคลื่อนที่ในแนวเส้นตรง โดยมีกราฟความเร็ว-เวลา (v-t) ดังนี้: ช่วงเวลา t = 0 ถึง 4 s ความเร็วเพิ่มขึ้นเชิงเส้นจาก 0 เป็น 12 m/s, ช่วง t = 4 ถึง 8 s ความเร็วคงที่ 12 m/s, และช่วง t = 8 ถึง 10 s ความเร็วลดลงอย่างสม่ำเสมอจนหยุดนิ่ง จงหาระยะกระจัดรวม (Displacement) ทั้งหมด และขนาดของแรงลัพธ์ในช่วง 2 วินาทีสุดท้าย',
    latexFormula: 's = \\int v\\,dt = \\text{Area under } v\\text{-}t \\quad , \\quad F = ma = m\\left(\\frac{dv}{dt}\\right)',
    diagramType: 'graph-physics',
    choices: [
      {
        id: 'c1',
        text: 'ระยะกระจัด 84 m และแรงลัพธ์ 12 N ในทิศตรงข้ามการเคลื่อนที่',
        latex: 's = 84\\text{ m}, \\quad F = 12\\text{ N}',
        isCorrect: true
      },
      {
        id: 'c2',
        text: 'ระยะกระจัด 96 m และแรงลัพธ์ 24 N',
        latex: 's = 96\\text{ m}, \\quad F = 24\\text{ N}',
        isCorrect: false,
        rootCauseError: 'คิดพื้นที่เป็นสี่เหลี่ยมผืนผ้าเต็มรูปแทนที่จะคิดพื้นที่รูปสี่เหลี่ยมคางหมู และลืมหารเวลาในการหาความเร่ง',
        remedialConcept: 'สูตรพื้นที่สี่เหลี่ยมคางหมู 1/2 * (ผลบวกด้านคู่ขนาน) * สูง'
      },
      {
        id: 'c3',
        text: 'ระยะกระจัด 72 m และแรงลัพธ์ 6 N',
        latex: 's = 72\\text{ m}, \\quad F = 6\\text{ N}',
        isCorrect: false,
        rootCauseError: 'ลืมคูณมวล m = 2 kg ในสูตร F = ma (ได้เฉพาะค่าความเร่ง a = 6 m/s^2)',
        remedialConcept: 'กฎข้อที่ 2 ของนิวตัน F_net = m * a'
      },
      {
        id: 'c4',
        text: 'ระยะกระจัด 84 m และแรงลัพธ์ 6 N',
        latex: 's = 84\\text{ m}, \\quad F = 6\\text{ N}',
        isCorrect: false,
        rootCauseError: 'หาระยะกระจัดถูก แต่ตอบเฉพาะขนาดความเร่ง a โดยไม่ได้คูณมวล',
        remedialConcept: 'การแยกแยะระหว่างความเร่ง (a) กับแรงลัพธ์ (F)'
      }
    ],
    explanation: '1. หาระยะกระจัดจากพื้นที่ใต้กราฟ v-t รูปสี่เหลี่ยมคางหมู:\n   Area = 1/2 * (ผลบวกด้านคู่ขนาน) * สูง\n   = 1/2 * [(10 - 0) + (8 - 4)] * 12\n   = 1/2 * [10 + 4] * 12 = 1/2 * 14 * 12 = 84 เมตร\n2. หาความเร่งในช่วง 2 วินาทีสุดท้าย (t = 8 ถึง 10 s):\n   a = (v_final - v_initial) / delta_t = (0 - 12) / (10 - 8) = -6 m/s^2\n3. หาขนาดแรงลัพธ์จากกฎของนิวตัน:\n   F = m * |a| = 2 kg * 6 m/s^2 = 12 นิวตัน (ทิศต้านการเคลื่อนที่)',
    rootCauseInsight: 'ข้อสอบฟิสิกส์ A-Level เน้นการเชื่อมโยงระหว่าง "ความหมายทางเรขาคณิตของกราฟ" (ความชัน = a, พื้นที่ = s) กับ "กฎของนิวตัน" (F = ma) การฝึกดูจุดตัดกราฟจะช่วยประหยัดเวลาทำข้อสอบได้ถึง 50%',
    remedialGuide: {
      foundationTopic: 'กราฟการเคลื่อนที่แนวตรง (s-t, v-t, a-t) & กฎนิวตัน',
      reviewTimeMinutes: 3,
      quickTip: 'จำคู่หู: ความชัน v-t คือ ความเร่ง (a) / พื้นที่ใต้กราฟ v-t คือ การกระจัด (s)',
      keyFormula: 's = \\text{Area}(v\\text{-}t) \\quad , \\quad F = m\\left(\\frac{\\Delta v}{\\Delta t}\\right)'
    }
  },

  // --- A-Level Math Parabola & Calculus Tangent ---
  {
    id: 'q-math-calc-1',
    examType: 'A-Level-Math1',
    examTypeCode: '61',
    examTypeNameTh: 'A-Level คณิตศาสตร์ประยุกต์ 1',
    topic: 'แคลคูลัส & สมการเส้นสัมผัสพาราโบลา/เส้นโค้ง',
    subTopic: 'การหาอนุพันธ์และจุดตัดแกนพิกัดฉาก',
    difficulty: 'Hard',
    question: 'กำหนดเส้นโค้ง f(x) = x^3 - 3x^2 + 5 จงหาสมการเส้นตรง L ที่สัมผัสกราฟ f(x) ณ จุดที่ x = 2 และหาว่าเส้นสัมผัส L นี้ตัดแกน Y ที่จุดพิกัดใด?',
    latexFormula: 'f\'(x_0) = m \\implies y - f(x_0) = m(x - x_0)',
    diagramType: 'graph-math',
    choices: [
      {
        id: 'c1',
        text: 'สมการคือ y = 1 และตัดแกน Y ที่จุด (0, 1)',
        latex: 'y = 1 \\quad , \\quad (0, 1)',
        isCorrect: true
      },
      {
        id: 'c2',
        text: 'สมการคือ y = -1 และตัดแกน Y ที่จุด (0, -1)',
        latex: 'y = -1 \\quad , \\quad (0, -1)',
        isCorrect: false,
        rootCauseError: 'ลืมบวกค่า f(x0) กลับเข้าไปหลังจากคิด m = 0 ทำให้ได้ y = -1 แทนที่จะเป็น y = 1',
        remedialConcept: 'การแทนค่าและสูตรสมการเส้นตรง y - y0 = m(x - x0)'
      },
      {
        id: 'c3',
        text: 'สมการคือ y = 5 และตัดแกน Y ที่จุด (0, 5)',
        latex: 'y = 5 \\quad , \\quad (0, 5)',
        isCorrect: false,
        rootCauseError: 'นำ x = 0 ไปแทนในสมการเดิม f(x) โดยไม่ได้หาสมการเส้นสัมผัสกราฟ',
        remedialConcept: 'นิยามของเส้นสัมผัสเส้นโค้ง (Tangent Line vs Y-intercept of function)'
      },
      {
        id: 'c4',
        text: 'สมการคือ y = 0x และตัดแกน Y ที่จุด (0, 0)',
        latex: 'y = 0 \\quad , \\quad (0, 0)',
        isCorrect: false,
        rootCauseError: 'เข้าใจผิดว่าเมื่อความชัน m = 0 เส้นตรงจะต้องตัดแกนที่ y = 0 เสมอ',
        remedialConcept: 'เส้นตรงความชันศูนย์ (Horizontal Line y = c)'
      }
    ],
    explanation: '1. หาพิกัดจุดสัมผัส: f(2) = 2^3 - 3(2)^2 + 5 = 8 - 12 + 5 = 1 ดังนั้นจุดสัมผัสคือ (2, 1)\n2. หาความชันเส้นสัมผัส m = f\'(2):\n   f\'(x) = 3x^2 - 6x\n   f\'(2) = 3(2)^2 - 6(2) = 12 - 12 = 0 (เส้นสัมผัสแนวนอน)\n3. หาสมการเส้นตรง L: y - 1 = 0 * (x - 2) -> y = 1\n4. จุดตัดแกน Y (แทน x = 0): ได้ y = 1 -> จุดตัดคือ (0, 1)',
    rootCauseInsight: 'สิ่งที่ทำให้เด็ก 60% ตอบผิดไม่ใช่เพราะไม่เข้าใจการดิฟ (Calculus) แต่เกิดจากการสับสนระหว่าง "จุดตัดแกนของฟังก์ชันเดิม" กับ "จุดตัดแกนของเส้นสัมผัส"',
    remedialGuide: {
      foundationTopic: 'เรขาคณิตวิเคราะห์: สมการเส้นตรง y - y1 = m(x - x1)',
      reviewTimeMinutes: 3,
      quickTip: 'จำง่ายๆ: ดิฟเพื่อหา "ความชัน (m)" แล้วนำไปเข้า "สูตรเส้นตรง" ก่อนหาจุดตัดเสมอ!',
      keyFormula: 'y - y_0 = f\'(x_0)(x - x_0)'
    }
  },

  // --- TPAT3 Spatial Net Folding ---
  {
    id: 'q-tpat3-dimension-1',
    examType: 'TPAT3',
    examTypeCode: '73',
    examTypeNameTh: 'TPAT3 ความถนัดวิศวกรรม/วิทยาศาสตร์',
    topic: 'มิติสัมพันธ์และแผนพับกล่อง (Cube Net Folding & Polyhedra)',
    subTopic: 'กฎคู่ตรงข้าม (Opposite Faces Rule) และการพับ 3 มิติ',
    difficulty: 'Hard',
    question: 'จากรูปคลี่ลูกบาศก์ (Net of Cube) รูปกางเขนมาตรฐาน ประกอบด้วยหน้า A, B, C, D, E, F โดยหน้า A อยู่ตรงข้ามกับหน้า F (คู่บน-ล่าง) และหน้า B อยู่ตรงข้ามกับหน้า D (คู่หน้า-หลัง) หากเรานำมาพับประกอบเป็นลูกบาศก์ 3 มิติ แล้วมองโดยให้หน้า A อยู่ด้านบน และหน้า B อยู่ด้านหน้า ข้อใดระบุหน้าทาง "ด้านขวา" ได้ถูกต้อง?',
    diagramType: 'spatial',
    choices: [
      { id: 'c1', text: 'หน้า C หรือ หน้า E ขึ้นอยู่กับทิศทางการพับเข้าหรือพับออก', isCorrect: true },
      { id: 'c2', text: 'หน้า F เสมอ', isCorrect: false, rootCauseError: 'หน้า F อยู่ตรงข้ามกับหน้า A (อยู่ด้านล่าง) ไม่สามารถอยู่ด้านขวาได้' },
      { id: 'c3', text: 'หน้า D เสมอ', isCorrect: false, rootCauseError: 'หน้า D อยู่ตรงข้ามกับหน้า B (อยู่ด้านหลัง) ไม่สามารถอยู่ด้านขวาได้' },
      { id: 'c4', text: 'หน้า B เสมอ', isCorrect: false, rootCauseError: 'หน้า B อยู่ด้านหน้าอยู่แล้ว ไม่สามารถซ้ำกับด้านขวาได้' }
    ],
    explanation: 'เนื่องจาก A อยู่ตรงข้ามกับ F (บน-ล่าง) และ B อยู่ตรงข้ามกับ D (หน้า-หลัง) ดังนั้นหน้าทางซ้ายและขวาจะต้องเป็นหน้า C และ E เสมอ โดยขึ้นอยู่กับว่าพับรูปคลี่ไปด้านหน้าหรือด้านหลัง',
    rootCauseInsight: 'ข้อสอบกระดาษทำให้เด็กมองไม่เห็นความสัมพันธ์แบบ 3 มิติ แต่ถ้าใช้กฎ Opposite Faces Rule: "คู่ตรงข้ามจะไม่มีวันอยู่ติดกัน" จะสามารถตัดชอยส์ที่ผิดทิ้งได้ทันทีใน 3 วินาที',
    remedialGuide: {
      foundationTopic: 'คู่ตรงข้ามของลูกบาศก์ (Opposite Faces Rule in 3D Net)',
      reviewTimeMinutes: 2,
      quickTip: 'บนคู่กับล่าง, หน้าคู่กับหลัง, ซ้ายคู่กับขวา! คู่ตรงข้ามจะไม่มีวันอยู่ติดกันในลูกบาศก์',
      keyFormula: '\\text{Pair}_1: (A \\leftrightarrow F), \\quad \\text{Pair}_2: (B \\leftrightarrow D), \\quad \\text{Pair}_3: (C \\leftrightarrow E)'
    }
  },

  // --- TGAT2 Logical Reasoning ---
  {
    id: 'q-tgat2-logic-1',
    examType: 'TGAT2',
    examTypeCode: '92',
    examTypeNameTh: 'TGAT2 การคิดอย่างมีเหตุผล (Logical Reasoning)',
    topic: 'การให้เหตุผลเชิงตรรกะและแผนภาพเซต (Venn Diagram)',
    subTopic: 'ตรรกศาสตร์นิรนัยและอุปนัย',
    difficulty: 'Medium',
    question: 'ข้อใดสรุปความได้อย่างสมเหตุสมผลที่สุดจากข้อความต่อไปนี้:\n"นักบินทุกคนต้องมีสายตาปกติ คนที่สายตาปกติบางคนเป็นนักว่ายน้ำ และไม่มีนักว่ายน้ำคนใดที่กลัวน้ำ"',
    choices: [
      {
        id: 'c1',
        text: 'คนที่สายตาปกติบางคนไม่กลัวน้ำ',
        isCorrect: true
      },
      {
        id: 'c2',
        text: 'นักบินทุกคนไม่กลัวน้ำ',
        isCorrect: false,
        rootCauseError: 'ด่วนสรุปจากเซตย่อย (Subset fallacy) เพราะนักบินไม่ได้เป็นสับเซตของนักว่ายน้ำทั้งหมด',
        remedialConcept: 'การวาดแผนภาพเวนน์-ออยเลอร์ (Venn Diagrams)'
      },
      {
        id: 'c3',
        text: 'นักบินบางคนเป็นนักว่ายน้ำ',
        isCorrect: false,
        rootCauseError: 'สรุปเอาเองโดยไม่มีข้อความเชื่อมโยงโดยตรงระหว่างนักบินกับนักว่ายน้ำ',
        remedialConcept: 'ตรรกศาสตร์: นิรนัย vs อุปนัย'
      },
      {
        id: 'c4',
        text: 'ไม่มีคนที่กลัวน้ำคนใดที่มีสายตาปกติ',
        isCorrect: false,
        rootCauseError: 'กลับประพจน์แบบผิดหลักตรรกศาสตร์ (Converse Error)',
        remedialConcept: 'การสมมูลและการนิเสธของประพจน์'
      }
    ],
    explanation: 'จากข้อความ: นักว่ายน้ำทุกคนเป็นคนที่ "ไม่กลัวน้ำ" และมี "คนที่สายตาปกติบางคน" ที่เป็นนักว่ายน้ำ ดังนั้น คนที่สายตาปกติกลุ่มนั้นย่อม "ไม่กลัวน้ำ" อย่างแน่นอน',
    rootCauseInsight: 'จุดบอดหลักของ TGAT2 คือการใช้อคติ/ความรู้สึกในชีวิตประจำวันมาตอบ แทนที่จะใช้วิธีวาดแผนภาพเซตเวนน์-ออยเลอร์',
    remedialGuide: {
      foundationTopic: 'วาดแผนภาพเวนน์-ออยเลอร์ 3 วง เพื่อตัดชอยส์',
      reviewTimeMinutes: 2,
      quickTip: 'ถ้ามีคำว่า "บางคน" ปรากฏ ห้ามสรุปเป็น "ทุกคน" เด็ดขาด!'
    }
  },

  // --- TGAT1 English Communication ---
  {
    id: 'q-tgat1-eng-1',
    examType: 'TGAT1',
    examTypeCode: '91',
    examTypeNameTh: 'TGAT1 การสื่อสารภาษาอังกฤษ (English Communication)',
    topic: 'Language Use & Sentence Structure (Subject-Verb Agreement & Inversion)',
    subTopic: 'Negative Inversion & Advanced Grammar',
    difficulty: 'Hard',
    question: 'Choose the best option to complete the formal academic report:\n"Rarely _______ such rapid advancements in artificial intelligence models that can simulate complex scientific phenomena."',
    choices: [
      {
        id: 'c1',
        text: 'have researchers witnessed',
        isCorrect: true
      },
      {
        id: 'c2',
        text: 'researchers have witnessed',
        isCorrect: false,
        rootCauseError: 'ลืมใช้โครงสร้าง Inversion (สลับกริยาช่วยมาหน้าประธาน) เมื่อขึ้นต้นประโยคด้วยคำบอกปฏิเสธ เช่น Rarely, Seldom, Never',
        remedialConcept: 'Negative Inversion Structure: Negative Adverb + Auxiliary + Subject + Main Verb'
      },
      {
        id: 'c3',
        text: 'researchers witnessing',
        isCorrect: false,
        rootCauseError: 'ใช้ Participle แทนกริยาแท้ ทำให้ประโยคขาด Finite Verb (Fragment sentence)',
        remedialConcept: 'Complete Sentence Structure (Subject + Finite Verb)'
      },
      {
        id: 'c4',
        text: 'witnessing researchers have',
        isCorrect: false,
        rootCauseError: 'การเรียงลำดับคำผิดหลักไวยากรณ์ภาษาอังกฤษอย่างสิ้นเชิง',
        remedialConcept: 'Word Order in English Grammar'
      }
    ],
    explanation: 'เมื่อประโยคเริ่มต้นด้วย Negative / Limiting Adverb เช่น Rarely, Seldom, Scarcely, Never จะต้องใช้โครงสร้าง "Inversion" โดยย้ายกริยาช่วย (have) มาไว้ข้างหน้าประธาน (researchers) -> "Rarely have researchers witnessed..."',
    rootCauseInsight: 'ข้อสอบ TGAT1 พาร์ต Text Completion มักนำไวยากรณ์ Inversion มาออกเพื่อคัดแยกกลุ่มนักเรียนคะแนนระดับท็อป 10%',
    remedialGuide: {
      foundationTopic: 'Negative Inversion (Rarely / Seldom / Hardley / Never + V.aux + S)',
      reviewTimeMinutes: 2,
      quickTip: 'เมื่อเห็นคำปฏิเสธขึ้นต้นประโยค มองหาข้อที่ "กริยาช่วยอยู่หน้าประธาน" ทันที!'
    }
  },

  // --- TPAT1 Medical Aptitude Ethics ---
  {
    id: 'q-tpat1-ethics-1',
    examType: 'TPAT1',
    examTypeCode: '71',
    examTypeNameTh: 'TPAT1 ความถนัดแพทย์ กสพท (จริยธรรมแพทย์)',
    topic: 'Medical Ethics & Patient Autonomy vs Beneficence',
    subTopic: 'การตัดสินใจในภาวะความยินยอมของผู้ป่วย (Informed Consent)',
    difficulty: 'Hard',
    question: 'ผู้ป่วยชายวัย 72 ปี มีสติดีครบถ้วน ตรวจพบมะเร็งลำไส้ระยะที่ 3 แพทย์แนะนำการผ่าตัดซึ่งมีโอกาสหาย 70% แต่ผู้ป่วยยืนยันปฏิเสธการรักษาและขอกลับไปใช้ชีวิตที่บ้านอย่างสงบ ขณะที่บุตรสาวซึ่งเป็นผู้ดูแลหลัก ร้องไห้ขอร้องให้แพทย์ผ่าตัดโดยไม่ต้องฟังคำปฏิเสธของบิดา ในฐานะแพทย์เจ้าของไข้ การกระทำใดถูกต้องตามหลักจริยธรรมสากลที่สุด?',
    choices: [
      {
        id: 'c1',
        text: 'เคารพการตัดสินใจของผู้ป่วย (Patient Autonomy) หลังจากประเมินว่าผู้ป่วยเข้าใจข้อมูล ผลดี-ผลเสียครบถ้วน และประสานทีม Palliative Care ดูแลแบบประคับประคอง',
        isCorrect: true
      },
      {
        id: 'c2',
        text: 'ดำเนินการผ่าตัดตามคำขอของบุตรสาว เพราะบุตรสาวเป็นผู้รับผิดชอบค่าใช้จ่ายและต้องการรักษาชีวิตบิดา (Beneficence)',
        isCorrect: false,
        rootCauseError: 'ละเมิดสิทธิและอำนาจการตัดสินใจในร่างกายของตัวผู้ป่วยเอง (Violation of Autonomy)',
        remedialConcept: 'หลัก Autonomy เหนือกว่าคำขอของญาติ ตราบใดที่ผู้ป่วยมี Competence สติดีครบถ้วน'
      },
      {
        id: 'c3',
        text: 'ส่งผู้ป่วยไปตรวจประเมินทางจิตเวชทันทีเพื่อชี้ว่าผู้ป่วยมีภาวะซึมเศร้าและไม่มีความสามารถในการตัดสินใจ',
        isCorrect: false,
        rootCauseError: 'การปฏิเสธการรักษาไม่ใช่หลักฐานของโรคจิตเวช และเป็นการบิดเบือนกระบวนการประเมิน',
        remedialConcept: 'Decisional Capacity Assessment'
      },
      {
        id: 'c4',
        text: 'ปฏิเสธที่จะดูแลผู้ป่วยรายนี้ต่อ เพราะผู้ป่วยไม่ให้ความร่วมมือตามแผนการรักษาของแพทย์',
        isCorrect: false,
        rootCauseError: 'การละทิ้งผู้ป่วย (Patient Abandonment) ขัดต่อจรรยาบรรณวิชาชีพแพทย์อย่างร้ายแรง',
        remedialConcept: 'Duty of Care & Non-Abandonment'
      }
    ],
    explanation: 'ตามหลักจริยธรรมแพทย์สากล 4 ประการ (Autonomy, Beneficence, Non-maleficence, Justice): เมื่อผู้ป่วยมีสติสัมปชัญญะสมบูรณ์ (Competent Adult) สิทธิในการตัดสินใจยอมรับหรือปฏิเสธการรักษาในร่างกายของตนเอง (Autonomy) ย่อมเป็นสิทธิเด็ดขาดของตัวผู้ป่วย ไม่สามารถถูกแทนที่ด้วยคำร้องขอของญาติได้',
    rootCauseInsight: 'ข้อสอบ TPAT1 กสพท มักสร้างโจทย์ขัดแย้งระหว่าง "ความหวังดีของญาติ (Beneficence)" กับ "สิทธิของผู้ป่วย (Autonomy)" คำตอบที่ถูกตามมาตรฐานสากลคือยึด Autonomy ของผู้ป่วยที่มีสติครบถ้วนเป็นหลักเสมอ',
    remedialGuide: {
      foundationTopic: 'จริยศาสตร์ทางการแพทย์ 4 เสาหลัก (Beauchamp & Childress Principles)',
      reviewTimeMinutes: 3,
      quickTip: 'ถ้าผู้ป่วยรู้เรื่อง มีสติดี -> สิทธิขาดอยู่ที่ "ตัวผู้ป่วย" ไม่ใช่ญาติหรือแพทย์!'
    }
  }
];

// 4. Target Faculty Weightings for ROI Calculation
export const TARGET_FACULTIES: TargetFacultyWeight[] = [
  {
    id: 'med-cotmes',
    name: 'แพทยศาสตร์ (กสพท)',
    university: 'จุฬาฯ / ศิริราช / รามาฯ / มข. / มช.',
    popularScoreTarget: 68.5,
    weights: [
      { subject: 'TPAT1 (วิชาเฉพาะแพทย์ กสพท)', subjectKey: 'tpat1', weightPercent: 30, typicalScore: 18, maxScore: 30 },
      { subject: 'A-Level คณิต 1 (ประยุกต์)', subjectKey: 'math1', weightPercent: 14, typicalScore: 7, maxScore: 14 },
      { subject: 'A-Level ภาษาอังกฤษ', subjectKey: 'eng', weightPercent: 14, typicalScore: 9, maxScore: 14 },
      { subject: 'A-Level ฟิสิกส์', subjectKey: 'physics', weightPercent: 9.33, typicalScore: 5, maxScore: 9.33 },
      { subject: 'A-Level เคมี', subjectKey: 'chem', weightPercent: 9.33, typicalScore: 5, maxScore: 9.33 },
      { subject: 'A-Level ชีววิทยา', subjectKey: 'bio', weightPercent: 9.33, typicalScore: 6, maxScore: 9.33 },
      { subject: 'A-Level ภาษาไทย & สังคม', subjectKey: 'thai_soc', weightPercent: 14, typicalScore: 9, maxScore: 14 }
    ]
  },
  {
    id: 'eng-chula',
    name: 'วิศวกรรมศาสตร์ (วิศวะรวม / คอมพิวเตอร์ / AI)',
    university: 'จุฬาลงกรณ์มหาวิทยาลัย / เกษตรศาสตร์ / ลาดกระบัง',
    popularScoreTarget: 72.0,
    weights: [
      { subject: 'TGAT (ความถนัดทั่วไป)', subjectKey: 'tgat', weightPercent: 20, typicalScore: 15, maxScore: 20 },
      { subject: 'TPAT3 (ความถนัดวิศวะ/วิทย์)', subjectKey: 'tpat3', weightPercent: 30, typicalScore: 21, maxScore: 30 },
      { subject: 'A-Level คณิต 1 (ประยุกต์)', subjectKey: 'math1', weightPercent: 20, typicalScore: 13, maxScore: 20 },
      { subject: 'A-Level ฟิสิกส์', subjectKey: 'physics', weightPercent: 20, typicalScore: 13, maxScore: 20 },
      { subject: 'A-Level เคมี', subjectKey: 'chem', weightPercent: 10, typicalScore: 6, maxScore: 10 }
    ]
  },
  {
    id: 'bba-tu',
    name: 'พาณิชยศาสตร์และการบัญชี / บริหารธุรกิจ (BBA)',
    university: 'มหาวิทยาลัยธรรมศาสตร์ / จุฬาลงกรณ์มหาวิทยาลัย',
    popularScoreTarget: 70.0,
    weights: [
      { subject: 'TGAT (ความถนัดทั่วไป)', subjectKey: 'tgat', weightPercent: 40, typicalScore: 30, maxScore: 40 },
      { subject: 'A-Level คณิต 1 หรือ คณิต 2', subjectKey: 'math1', weightPercent: 30, typicalScore: 19, maxScore: 30 },
      { subject: 'A-Level ภาษาอังกฤษ', subjectKey: 'eng', weightPercent: 30, typicalScore: 21, maxScore: 30 }
    ]
  },
  {
    id: 'comm-arts-cu',
    name: 'นิเทศศาสตร์ / วารสารศาสตร์และสื่อสารมวลชน',
    university: 'จุฬาลงกรณ์มหาวิทยาลัย / มหาวิทยาลัยธรรมศาสตร์',
    popularScoreTarget: 74.0,
    weights: [
      { subject: 'TGAT (ความถนัดทั่วไป)', subjectKey: 'tgat', weightPercent: 50, typicalScore: 40, maxScore: 50 },
      { subject: 'A-Level ภาษาอังกฤษ', subjectKey: 'eng', weightPercent: 25, typicalScore: 19, maxScore: 25 },
      { subject: 'A-Level ภาษาไทย / สังคม', subjectKey: 'thai_soc', weightPercent: 25, typicalScore: 18, maxScore: 25 }
    ]
  },
  {
    id: 'arch-chula',
    name: 'สถาปัตยกรรมศาสตร์ (สถ.บ.)',
    university: 'จุฬาลงกรณ์มหาวิทยาลัย / ศิลปากร / พระจอมเกล้า',
    popularScoreTarget: 71.5,
    weights: [
      { subject: 'TPAT4 (ความถนัดสถาปัตยกรรม)', subjectKey: 'tpat4', weightPercent: 40, typicalScore: 28, maxScore: 40 },
      { subject: 'TGAT (ความถนัดทั่วไป)', subjectKey: 'tgat', weightPercent: 20, typicalScore: 14, maxScore: 20 },
      { subject: 'A-Level คณิต 1', subjectKey: 'math1', weightPercent: 20, typicalScore: 13, maxScore: 20 },
      { subject: 'A-Level ฟิสิกส์', subjectKey: 'physics', weightPercent: 20, typicalScore: 13, maxScore: 20 }
    ]
  }
];
