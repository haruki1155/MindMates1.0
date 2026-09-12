class GuidanceSurveySection {
  const GuidanceSurveySection({required this.title, required this.questions});

  final String title;
  final List<String> questions;
}

const guidanceSurveySections = <GuidanceSurveySection>[
  GuidanceSurveySection(
    title: 'Information Service',
    questions: [
      'Disseminates current and correct information on curriculum offerings, financial opportunities, and school regulations.',
      'Makes available relevant information to help improve students themselves and their relationships.',
      'Gives comprehensive information regarding agencies and people to whom clients can be referred.',
      'Provides a wide variety of information about the university through the Orientation Program for freshmen and transferee students.',
      'Conducts mini-seminars or lectures for students’ personal-social development.',
      'Disseminates information on educational concerns such as school entrance requirements.',
      'Disseminates information on scholarships, grants, school uniforms, and the academic calendar.',
      'Covers vocational and occupational opportunities a student can pursue after college, including job openings, employment possibilities, and requirements.',
      'Uses local media such as regional television or local radio to inform students about their educational and academic needs.',
      'Distributes flyers, leaflets, or brochures about university administration, guidance programs, and other relevant information needed by students.',
    ],
  ),
  GuidanceSurveySection(
    title: 'Individual Inventory Service',
    questions: [
      'Distributes a personal data sheet to incoming freshmen and transferee students during enrollment.',
      'Is concerned with students’ health data by having them complete the university clinic’s medical form.',
      'Stores students’ data through a computer device for easier access when needed.',
      'Stores student information in a cumulative folder where data is kept during their university stay and for a few years afterward.',
      'Helps each client develop deeper, fuller self-awareness through guidance forms completed by students.',
      'Helps students create appropriate plans to improve their quality of life based on awareness and self-understanding.',
      'Provides administration and department heads with insight into suitable strategies for responding to students’ needs, interests, and values.',
      'Helps parents or guardians respond more sensitively to their children when problems arise.',
      'Conducts structured interviews to obtain specific information and in-depth behavioral responses from clients.',
      'Keeps entrance test results properly for accurate diagnosis and placement.',
    ],
  ),
  GuidanceSurveySection(
    title: 'Counseling Service',
    questions: [
      'Conducts the type of counseling needed by clients: career or occupational, educational or academic, and personal or social.',
      'Responds to self-initiated counseling sessions.',
      'Plans group counseling sessions for individuals with similar needs.',
      'Uses available human resources by establishing a peer facilitation or counseling program.',
      'Respects the confidentiality of information provided by clients.',
      'Refers students to a significant person in the university whenever specialized attention is needed.',
      'Uses appropriate guidance forms when conducting counseling sessions.',
      'Helps students understand course options and their impact on future plans.',
      'Has trained guidance personnel available to speak with students about personal problems.',
      'Initiates contact between teacher referral sources and individuals who have been referred.',
    ],
  ),
  GuidanceSurveySection(
    title: 'Placement Service',
    questions: [
      'Works with teachers and administrators to place students in appropriate courses, programs, and year levels.',
      'Assists individuals in making wise choices and taking the necessary steps for admission into a school or entry into their chosen workplace.',
      'Conducts training sessions on résumé writing, test-taking behavior, personality development, and related topics.',
      'Works with families and management in identifying, referring, placing, and following up individuals with special needs.',
      'Works with agencies to properly identify and place those who need rehabilitation.',
      'Assists graduating students who plan to pursue postgraduate studies with requirements and other concerns.',
      'Helps students who have been delisted from their major field of study and need to shift.',
      'Conducts career orientation activities such as the Quality, Productivity and Enhancement Seminar for graduating students.',
      'Coordinates with reputable agencies and industries in conducting job fairs.',
      'Posts and disseminates job openings through bulletin board announcements.',
    ],
  ),
  GuidanceSurveySection(
    title: 'Follow-up Service',
    questions: [
      'Tracks where graduates go after leaving school.',
      'Tracks where school dropouts or leavers go.',
      'Determines how well graduates are doing in their jobs.',
      'Identifies adjustment difficulties and concerns of graduates and school leavers or dropouts.',
      'Identifies problems and concerns of those who do not pursue a college course.',
      'Finds out where those who do not attend college go and what they do.',
      'Determines employer or agency satisfaction with graduates.',
      'Determines how long graduates stay in their jobs.',
      'Identifies additional knowledge and skills required by jobs that the school did not offer.',
      'Identifies reasons for dropping out or leaving school.',
    ],
  ),
  GuidanceSurveySection(
    title: 'Referral Service',
    questions: [
      'Coordinates with the receiving professional, agency, or office and provides information that facilitates the referral process.',
      'Refers clients who need psychological contact to relevant professionals, including a University Psychologist, for further evaluation and assessment.',
      'Willingly accommodates referrals from personnel within the university without prejudice.',
      'Informs clients that their status will be handled with utmost confidentiality throughout the referral process.',
      'Clearly explains the purpose of the referral to clients.',
      'Monitors the client’s progress by securing status information from the professional, agency, or organization receiving the referral.',
      'Updates the referrer on the status of a referral by sending a duly accomplished reply form.',
      'Ensures the client has agreed to the referral and its terms as stated in the counseling confidentiality statement.',
      'Ensures oral and written communications about the referral are clear and accurate.',
      'Does not interfere with the work of referred offices unless assistance is needed.',
    ],
  ),
];

const guidanceSurveyRatingLabels = <int, String>{
  5: 'Very much satisfied',
  4: 'Very satisfied',
  3: 'Moderately satisfied',
  2: 'Slightly satisfied',
  1: 'Not satisfied',
};
