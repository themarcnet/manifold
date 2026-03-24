#!/usr/bin/env python3
"""
Comprehensive Pitch Detection Algorithms Report Generator
"""

from reportlab.lib.pagesizes import letter
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, PageBreak, 
    Table, TableStyle
)
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_JUSTIFY
from reportlab.lib import colors
from reportlab.lib.units import inch
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfbase.pdfmetrics import registerFontFamily
import os

# Register fonts
pdfmetrics.registerFont(TTFont('Times New Roman', '/usr/share/fonts/truetype/english/Times-New-Roman.ttf'))
pdfmetrics.registerFont(TTFont('Microsoft YaHei', '/usr/share/fonts/truetype/chinese/msyh.ttf'))
pdfmetrics.registerFont(TTFont('SimHei', '/usr/share/fonts/truetype/chinese/SimHei.ttf'))
pdfmetrics.registerFont(TTFont('DejaVuSans', '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf'))

# Register font families for bold/superscript/subscript
registerFontFamily('Times New Roman', normal='Times New Roman', bold='Times New Roman')
registerFontFamily('SimHei', normal='SimHei', bold='SimHei')

def create_styles():
    styles = getSampleStyleSheet()
    
    # Cover title
    styles.add(ParagraphStyle(
        name='CoverTitle',
        fontName='Times New Roman',
        fontSize=36,
        leading=44,
        alignment=TA_CENTER,
        spaceAfter=30
    ))
    
    # Cover subtitle
    styles.add(ParagraphStyle(
        name='CoverSubtitle',
        fontName='Times New Roman',
        fontSize=18,
        leading=24,
        alignment=TA_CENTER,
        spaceAfter=40
    ))
    
    # Heading 1
    styles.add(ParagraphStyle(
        name='Heading1Custom',
        fontName='Times New Roman',
        fontSize=18,
        leading=24,
        spaceBefore=24,
        spaceAfter=12,
        textColor=colors.HexColor('#1F4E79')
    ))
    
    # Heading 2
    styles.add(ParagraphStyle(
        name='Heading2Custom',
        fontName='Times New Roman',
        fontSize=14,
        leading=18,
        spaceBefore=18,
        spaceAfter=8,
        textColor=colors.HexColor('#2E75B6')
    ))
    
    # Body text - renamed to avoid collision
    styles.add(ParagraphStyle(
        name='BodyCustom',
        fontName='Times New Roman',
        fontSize=11,
        leading=16,
        alignment=TA_JUSTIFY,
        spaceBefore=6,
        spaceAfter=6
    ))
    
    # Table header
    styles.add(ParagraphStyle(
        name='TableHeader',
        fontName='Times New Roman',
        fontSize=10,
        leading=12,
        alignment=TA_CENTER,
        textColor=colors.white
    ))
    
    # Table cell
    styles.add(ParagraphStyle(
        name='TableCell',
        fontName='Times New Roman',
        fontSize=10,
        leading=12,
        alignment=TA_LEFT
    ))
    
    # Table cell center
    styles.add(ParagraphStyle(
        name='TableCellCenter',
        fontName='Times New Roman',
        fontSize=10,
        leading=12,
        alignment=TA_CENTER
    ))
    
    # Caption
    styles.add(ParagraphStyle(
        name='Caption',
        fontName='Times New Roman',
        fontSize=10,
        leading=12,
        alignment=TA_CENTER,
        textColor=colors.HexColor('#666666'),
        spaceBefore=6,
        spaceAfter=12
    ))
    
    return styles

def create_cover_page(story, styles):
    story.append(Spacer(1, 120))
    story.append(Paragraph("<b>Audio Pitch Detection Algorithms</b>", styles['CoverTitle']))
    story.append(Paragraph("A Comprehensive Guide for Audio Application<br/>and VST Development", styles['CoverSubtitle']))
    story.append(Spacer(1, 60))
    story.append(Paragraph("Research Report", styles['CoverSubtitle']))
    story.append(Spacer(1, 30))
    story.append(Paragraph("Classical Methods | Modern Techniques | Industry Standards", styles['BodyCustom']))
    story.append(PageBreak())

def create_introduction(story, styles):
    story.append(Paragraph("<b>1. Introduction</b>", styles['Heading1Custom']))
    
    intro_text = """
    Pitch detection is a fundamental component in audio processing applications, forming the backbone of technologies ranging from guitar tuners to professional pitch correction software used in music production. The ability to accurately and efficiently estimate the fundamental frequency (F0) of an audio signal is crucial for applications in speech recognition, music information retrieval, automatic transcription, and real-time audio effects processing.
    """
    story.append(Paragraph(intro_text, styles['BodyCustom']))
    
    story.append(Paragraph("<b>1.1 What is Pitch Detection?</b>", styles['Heading2Custom']))
    
    what_is_text = """
    Pitch detection, also known as fundamental frequency estimation, is the process of determining the perceived frequency of a sound wave that corresponds to its musical note. In technical terms, it involves analyzing an audio signal to find its fundamental frequency (F0) - the lowest frequency component that determines the perceived pitch of a sound. This is distinct from simply finding the dominant frequency, as musical sounds contain multiple harmonic overtones that can complicate the analysis.
    """
    story.append(Paragraph(what_is_text, styles['BodyCustom']))
    
    story.append(Paragraph("<b>1.2 Applications in Audio Software</b>", styles['Heading2Custom']))
    
    applications_text = """
    Modern audio applications leverage pitch detection in numerous ways. Real-time pitch correction plugins like Antares Auto-Tune and Celemony Melodyne rely on accurate pitch detection to identify and correct off-key notes in vocal performances. Guitar tuners and instrument training applications use simplified versions of these algorithms to provide visual feedback to musicians. In music information retrieval, pitch detection enables automatic transcription of melodies and chord recognition. Voice-controlled systems use pitch analysis for speaker identification and emotion detection. The gaming industry employs pitch detection for singing games and interactive music applications where player input must be evaluated in real-time.
    """
    story.append(Paragraph(applications_text, styles['BodyCustom']))
    
    story.append(Paragraph("<b>1.3 Challenges in Pitch Detection</b>", styles['Heading2Custom']))
    
    challenges_text = """
    Pitch detection presents several significant challenges that have driven decades of research. The octave error problem occurs when an algorithm misidentifies a frequency as being an octave higher or lower than its true value. Harmonic interference happens when the harmonics of a sound are stronger than the fundamental frequency, leading to incorrect estimates. Noise robustness remains a critical concern, as real-world audio signals often contain background noise, room acoustics, and recording artifacts that can confuse detection algorithms. Computational efficiency is particularly important for real-time applications where latency must be minimized. Additionally, handling both monophonic and polyphonic signals requires different approaches, with polyphonic pitch detection remaining an active area of research.
    """
    story.append(Paragraph(challenges_text, styles['BodyCustom']))
    
    story.append(Spacer(1, 12))

def create_classical_algorithms(story, styles):
    story.append(Paragraph("<b>2. Classical Time-Domain Algorithms</b>", styles['Heading1Custom']))
    
    intro_text = """
    Time-domain algorithms analyze the audio waveform directly without converting it to the frequency domain. These methods are generally computationally efficient and well-suited for real-time applications, making them popular choices for embedded systems and real-time audio processing.
    """
    story.append(Paragraph(intro_text, styles['BodyCustom']))
    
    # Zero-Crossing Rate
    story.append(Paragraph("<b>2.1 Zero-Crossing Rate (ZCR)</b>", styles['Heading2Custom']))
    
    zcr_text = """
    The Zero-Crossing Rate method is the simplest approach to pitch detection. It operates by counting the number of times the audio signal crosses the zero amplitude line within a given time window. The frequency is estimated by dividing the crossing count by twice the duration of the analysis window, as each complete waveform cycle produces two zero crossings. Despite its computational simplicity (O(n) complexity), this method has significant limitations. It performs poorly on signals with multiple harmonics, as additional frequency components create extra zero crossings that distort the count. The method is also highly sensitive to noise and DC offset in the signal. Zero-crossing detection is best suited for simple sinusoidal signals or educational demonstrations where accuracy is less critical than simplicity.
    """
    story.append(Paragraph(zcr_text, styles['BodyCustom']))
    
    # Autocorrelation
    story.append(Paragraph("<b>2.2 Autocorrelation Method</b>", styles['Heading2Custom']))
    
    ac_text = """
    Autocorrelation-based pitch detection is one of the most widely used classical methods, dating back to the foundational work of Rabiner and Schafer in the 1970s. The algorithm operates by computing the correlation between the signal and time-shifted versions of itself. When the time shift corresponds to one period of the fundamental frequency, the signal aligns with itself, producing a peak in the autocorrelation function. The location of this peak indicates the pitch period, from which the frequency can be derived. The algorithm has O(n squared) computational complexity for the naive implementation, though efficient variants using FFT can reduce this. Autocorrelation is robust for periodic signals and performs well on speech and musical instruments. However, it can suffer from octave errors and requires careful peak selection logic to avoid identifying harmonics as the fundamental. The method is widely used in speech processing systems and forms the basis for many subsequent improvements.
    """
    story.append(Paragraph(ac_text, styles['BodyCustom']))
    
    # YIN
    story.append(Paragraph("<b>2.3 YIN Algorithm</b>", styles['Heading2Custom']))
    
    yin_text = """
    The YIN algorithm, introduced by de Cheveigne and Kawahara in their seminal 2002 paper, represents a significant advancement over basic autocorrelation methods. The name YIN derives from the Chinese philosophical concept of Yin-Yang, symbolizing the algorithm's approach of distinguishing between two possibilities at each decision point. YIN modifies the autocorrelation approach by using a difference function instead of a product function, which provides better discrimination between true periods and their multiples. The algorithm then applies cumulative mean normalization to the difference function, which helps prevent octave errors by making the threshold adaptive rather than fixed. Parabolic interpolation is applied to achieve sub-sample accuracy, improving frequency resolution beyond the discrete sampling rate limitations. YIN provides a threshold parameter that allows users to balance between false positive rate and sensitivity. With proper threshold tuning (typically around 0.15), YIN achieves accuracy comparable to more computationally intensive methods while maintaining real-time capability. It has been widely adopted in research tools and audio processing libraries including Librosa and Aubio.
    """
    story.append(Paragraph(yin_text, styles['BodyCustom']))
    
    # NSDF
    story.append(Paragraph("<b>2.4 NSDF (McLeod Pitch Method)</b>", styles['Heading2Custom']))
    
    nsdf_text = """
    The Normalized Square Difference Function method, developed by McLeod and Wyvill in 2005, combines aspects of autocorrelation with normalization to achieve robust pitch detection. The algorithm computes a normalized correlation function that remains bounded between -1 and 1 regardless of signal amplitude. This normalization makes the method inherently amplitude-invariant, eliminating the need for signal level adjustment or threshold calibration for different input levels. The method identifies pitch by finding peaks in the NSDF function above a specified threshold, then applying parabolic interpolation for refined frequency estimation. NSDF performs particularly well on musical instrument signals and has found application in real-time guitar tuners and similar embedded audio devices. The algorithm shares YIN's O(n squared) computational complexity but offers slightly different trade-offs in terms of false positive and false negative rates for various signal types.
    """
    story.append(Paragraph(nsdf_text, styles['BodyCustom']))
    
    story.append(Spacer(1, 12))

def create_frequency_domain(story, styles):
    story.append(Paragraph("<b>3. Frequency Domain Methods</b>", styles['Heading1Custom']))
    
    intro_text = """
    Frequency domain methods transform the audio signal using the Fast Fourier Transform (FFT) before analysis. These approaches can leverage spectral information to distinguish between fundamental frequencies and their harmonics, offering different trade-offs compared to time-domain methods.
    """
    story.append(Paragraph(intro_text, styles['BodyCustom']))
    
    # HPS
    story.append(Paragraph("<b>3.1 Harmonic Product Spectrum (HPS)</b>", styles['Heading2Custom']))
    
    hps_text = """
    The Harmonic Product Spectrum method exploits the harmonic structure of pitched sounds to identify the fundamental frequency. Developed from work by Schroeder in the 1960s, HPS operates by computing multiple downsampled versions of the magnitude spectrum and multiplying them together. This multiplication amplifies the fundamental frequency peak while suppressing non-harmonic components. Specifically, if a signal has a fundamental at frequency f with harmonics at 2f, 3f, and so on, then downsampling the spectrum by factors of 2, 3, 4, etc., and multiplying the results will create a strong peak at the fundamental. The method has O(n log n) computational complexity when using FFT, making it efficient for longer analysis windows. HPS works well for signals with strong harmonic content, such as voiced speech and many musical instruments. However, it can struggle with inharmonic sounds, missing fundamentals, or signals where higher harmonics are significantly attenuated. The method is commonly used in music information retrieval systems and provides a good balance between accuracy and computational efficiency.
    """
    story.append(Paragraph(hps_text, styles['BodyCustom']))
    
    # Cepstrum
    story.append(Paragraph("<b>3.2 Cepstral Analysis</b>", styles['Heading2Custom']))
    
    cepstrum_text = """
    Cepstral analysis, introduced by Bogert, Healy, and Tukey in the 1960s, provides another approach to pitch detection in the frequency domain. The cepstrum is computed by taking the inverse Fourier transform of the log magnitude spectrum. In the cepstral domain, the periodic structure of harmonics in the original spectrum appears as a distinct peak at the quefrency (cepstral domain analogue of frequency) corresponding to the pitch period. This technique effectively separates the excitation source (the pitch) from the vocal tract or instrument body characteristics in the signal. Cepstral pitch detection is particularly useful in speech processing where it can separate glottal excitation from vocal tract filtering. The method has O(n log n) complexity but requires sufficient frequency resolution in the original FFT to accurately identify the pitch peak in the cepstrum. While not as commonly used in modern real-time applications, cepstral analysis remains important in speech analysis and synthesis systems.
    """
    story.append(Paragraph(cepstrum_text, styles['BodyCustom']))
    
    story.append(Spacer(1, 12))

def create_deep_learning(story, styles):
    story.append(Paragraph("<b>4. Deep Learning Approaches</b>", styles['Heading1Custom']))
    
    intro_text = """
    Recent advances in deep learning have produced neural network-based pitch detection systems that can achieve state-of-the-art accuracy by learning complex patterns directly from data. These methods typically require significant computational resources for training but can offer improved robustness and accuracy during inference.
    """
    story.append(Paragraph(intro_text, styles['BodyCustom']))
    
    # CREPE
    story.append(Paragraph("<b>4.1 CREPE</b>", styles['Heading2Custom']))
    
    crepe_text = """
    CREPE (Convolutional Representation for Pitch Estimation), introduced by Kim, Guitar, and colleagues in 2018, represents a breakthrough in data-driven pitch detection. The model employs a deep convolutional neural network that operates directly on time-domain waveforms, eliminating the need for hand-crafted features. CREPE was trained on a massive dataset of annotated audio and learns to map raw audio frames to pitch probability distributions across a discretized set of frequencies. The network architecture consists of multiple convolutional layers that progressively extract hierarchical features from the input signal. CREPE outputs a 360-dimensional activation matrix representing pitch probabilities across a range of frequencies, with a 10-cent resolution. This probabilistic output enables post-processing techniques like Viterbi decoding for smooth pitch tracks. CREPE has been shown to outperform traditional methods like pYIN and SWIPE on benchmark datasets, particularly for challenging signals with noise, reverb, or weak fundamental frequencies. The model is available as open-source software and has been integrated into music analysis tools like Librosa. However, CREPE's computational requirements are significantly higher than traditional methods, making it less suitable for resource-constrained real-time applications without optimization.
    """
    story.append(Paragraph(crepe_text, styles['BodyCustom']))
    
    # PESTO
    story.append(Paragraph("<b>4.2 PESTO</b>", styles['Heading2Custom']))
    
    pesto_text = """
    PESTO (Pitch Estimation with Self-supervised Training) represents a more recent advancement in neural pitch estimation. Developed with a focus on real-time applicability, PESTO uses self-supervised learning techniques to train models that can achieve high accuracy with reduced computational overhead compared to CREPE. The self-supervised approach allows the model to learn from unlabeled audio data, potentially enabling training on much larger datasets than would be feasible with manual annotation. PESTO has shown promising results in balancing the accuracy benefits of deep learning with the efficiency requirements of real-time audio processing. Research by Stefani and Turchet has demonstrated that PESTO can achieve near state-of-the-art accuracy while maintaining real-time performance suitable for VST plugin implementation.
    """
    story.append(Paragraph(pesto_text, styles['BodyCustom']))
    
    # SwiftF0
    story.append(Paragraph("<b>4.3 SwiftF0</b>", styles['Heading2Custom']))
    
    swift_text = """
    SwiftF0 is a recent addition to the pitch detection landscape, introduced in 2025 with a focus on combining speed and accuracy for monophonic pitch detection. The algorithm has been evaluated against classical methods including Praat, RAPT, SWIPE, YAAPT, and pYIN, demonstrating competitive or superior performance. SwiftF0 represents the continuing evolution of pitch detection algorithms that balance computational efficiency with accuracy, making it particularly relevant for real-time applications where both factors are critical.
    """
    story.append(Paragraph(swift_text, styles['BodyCustom']))
    
    story.append(Spacer(1, 12))

def create_comparison_table(story, styles):
    story.append(Paragraph("<b>5. Algorithm Comparison</b>", styles['Heading1Custom']))
    
    comparison_text = """
    The following table provides a comprehensive comparison of the major pitch detection algorithms discussed in this report, highlighting their key characteristics and suitability for different applications.
    """
    story.append(Paragraph(comparison_text, styles['BodyCustom']))
    
    story.append(Spacer(1, 12))
    
    # Table data
    header_style = styles['TableHeader']
    cell_style = styles['TableCell']
    cell_center = styles['TableCellCenter']
    
    data = [
        [
            Paragraph('<b>Algorithm</b>', header_style),
            Paragraph('<b>Domain</b>', header_style),
            Paragraph('<b>Complexity</b>', header_style),
            Paragraph('<b>Accuracy</b>', header_style),
            Paragraph('<b>Real-time</b>', header_style),
            Paragraph('<b>Best Use Case</b>', header_style)
        ],
        [
            Paragraph('Zero-Crossing', cell_style),
            Paragraph('Time', cell_center),
            Paragraph('O(n)', cell_center),
            Paragraph('Low', cell_center),
            Paragraph('Excellent', cell_center),
            Paragraph('Simple sine waves', cell_style)
        ],
        [
            Paragraph('Autocorrelation', cell_style),
            Paragraph('Time', cell_center),
            Paragraph('O(n<super>2</super>)', cell_center),
            Paragraph('Medium', cell_center),
            Paragraph('Good', cell_center),
            Paragraph('Speech, instruments', cell_style)
        ],
        [
            Paragraph('YIN', cell_style),
            Paragraph('Time', cell_center),
            Paragraph('O(n<super>2</super>)', cell_center),
            Paragraph('High', cell_center),
            Paragraph('Good', cell_center),
            Paragraph('Professional audio', cell_style)
        ],
        [
            Paragraph('HPS', cell_style),
            Paragraph('Frequency', cell_center),
            Paragraph('O(n log n)', cell_center),
            Paragraph('Medium-High', cell_center),
            Paragraph('Medium', cell_center),
            Paragraph('Harmonic signals', cell_style)
        ],
        [
            Paragraph('NSDF', cell_style),
            Paragraph('Time', cell_center),
            Paragraph('O(n<super>2</super>)', cell_center),
            Paragraph('High', cell_center),
            Paragraph('Good', cell_center),
            Paragraph('Musical instruments', cell_style)
        ],
        [
            Paragraph('CREPE', cell_style),
            Paragraph('Neural', cell_center),
            Paragraph('High', cell_center),
            Paragraph('Very High', cell_center),
            Paragraph('Limited', cell_center),
            Paragraph('Research, offline', cell_style)
        ],
        [
            Paragraph('PESTO', cell_style),
            Paragraph('Neural', cell_center),
            Paragraph('Medium', cell_center),
            Paragraph('High', cell_center),
            Paragraph('Good', cell_center),
            Paragraph('Real-time VST', cell_style)
        ],
    ]
    
    table = Table(data, colWidths=[1.1*inch, 0.8*inch, 0.85*inch, 0.8*inch, 0.7*inch, 1.2*inch])
    table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#1F4E79')),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
        ('BACKGROUND', (0, 1), (-1, 1), colors.white),
        ('BACKGROUND', (0, 2), (-1, 2), colors.HexColor('#F5F5F5')),
        ('BACKGROUND', (0, 3), (-1, 3), colors.white),
        ('BACKGROUND', (0, 4), (-1, 4), colors.HexColor('#F5F5F5')),
        ('BACKGROUND', (0, 5), (-1, 5), colors.white),
        ('BACKGROUND', (0, 6), (-1, 6), colors.HexColor('#F5F5F5')),
        ('BACKGROUND', (0, 7), (-1, 7), colors.white),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.grey),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('LEFTPADDING', (0, 0), (-1, -1), 6),
        ('RIGHTPADDING', (0, 0), (-1, -1), 6),
        ('TOPPADDING', (0, 0), (-1, -1), 6),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 6),
    ]))
    
    story.append(table)
    story.append(Paragraph("Table 1: Comparison of Pitch Detection Algorithms", styles['Caption']))
    
    story.append(Spacer(1, 12))

def create_vst_section(story, styles):
    story.append(Paragraph("<b>6. Implementation for VST Development</b>", styles['Heading1Custom']))
    
    vst_intro = """
    When implementing pitch detection for VST plugins, several practical considerations must be addressed beyond algorithm selection. The real-time constraints of audio processing demand careful attention to latency, CPU usage, and integration with the host Digital Audio Workstation (DAW).
    """
    story.append(Paragraph(vst_intro, styles['BodyCustom']))
    
    story.append(Paragraph("<b>6.1 Framework Selection</b>", styles['Heading2Custom']))
    
    framework_text = """
    Several frameworks are commonly used for VST development. JUCE is the most popular cross-platform framework for audio application and plugin development, providing comprehensive abstractions for audio processing, GUI development, and plugin format support (VST3, AU, AAX). The Steinberg VST SDK provides the official development kit for VST3 plugins, offering direct access to the VST specification. iPlug2 is a modern C++ framework that offers a lightweight alternative with support for various plugin formats. RTAudio provides cross-platform audio I/O for standalone applications. For pitch detection specifically, these frameworks can be combined with algorithm implementations from libraries like Aubio (C library), Librosa (Python), or custom implementations.
    """
    story.append(Paragraph(framework_text, styles['BodyCustom']))
    
    story.append(Paragraph("<b>6.2 Real-Time Considerations</b>", styles['Heading2Custom']))
    
    realtime_text = """
    Real-time pitch detection in VST plugins requires careful management of processing latency. The audio buffer size determines the fundamental trade-off between latency and frequency resolution. Smaller buffers reduce latency but provide fewer samples for analysis, potentially reducing accuracy. For pitch detection, typical buffer sizes range from 512 to 4096 samples, corresponding to approximately 12-93 milliseconds at 44.1 kHz sample rate. Overlap-add techniques can provide smoother pitch tracking by processing overlapping windows. CPU optimization techniques include using FFT-based autocorrelation for O(n log n) complexity, implementing circular buffers to minimize memory allocation, and using SIMD instructions for parallel computation where available.
    """
    story.append(Paragraph(realtime_text, styles['BodyCustom']))
    
    story.append(Paragraph("<b>6.3 Algorithm Recommendations</b>", styles['Heading2Custom']))
    
    recommendations_text = """
    For VST pitch detection applications, the choice of algorithm depends on the specific use case. For guitar tuners and simple instrument detection, YIN provides an excellent balance of accuracy and efficiency. For vocal pitch correction, consider YIN or pYIN with Viterbi smoothing for cleaner pitch tracks. For polyphonic scenarios, deep learning methods like CREPE or PESTO may be necessary. For resource-constrained embedded systems, optimized autocorrelation or NSDF may be preferred. Testing on diverse audio material including various instruments, noise conditions, and dynamic ranges is essential for robust performance.
    """
    story.append(Paragraph(recommendations_text, styles['BodyCustom']))
    
    story.append(Spacer(1, 12))

def create_industry_section(story, styles):
    story.append(Paragraph("<b>7. Industry Tools and Standards</b>", styles['Heading1Custom']))
    
    industry_text = """
    The commercial audio software industry has developed several pitch correction and detection tools that serve as benchmarks for algorithm performance. Understanding these tools provides insight into real-world algorithm selection and implementation strategies.
    """
    story.append(Paragraph(industry_text, styles['BodyCustom']))
    
    story.append(Paragraph("<b>7.1 Commercial Solutions</b>", styles['Heading2Custom']))
    
    commercial_text = """
    Antares Auto-Tune remains the industry standard for pitch correction, originally released in 1997 and continuously refined. The software combines pitch detection with pitch shifting and correction algorithms, offering both automatic and graphical editing modes. Celemony Melodyne provides advanced pitch and time manipulation with a unique approach that allows editing of individual notes within polyphonic material. Waves Tune Real-Time offers low-latency pitch correction designed for live performance applications. Serato Pitch'n'Time is recognized as an industry standard for high-quality time-stretching and pitch-shifting, often used in post-production.
    """
    story.append(Paragraph(commercial_text, styles['BodyCustom']))
    
    story.append(Paragraph("<b>7.2 Open Source Libraries</b>", styles['Heading2Custom']))
    
    opensource_text = """
    Several open source libraries provide pitch detection implementations suitable for integration into custom applications. Librosa is a Python library for audio analysis that includes pYIN implementation with Viterbi smoothing for robust pitch tracking. Aubio is a C library designed for real-time audio labeling, including pitch detection using YIN and other methods. CREPE is available as open source Python code with pre-trained models. These libraries provide well-tested implementations that can serve as references or be integrated directly into production systems.
    """
    story.append(Paragraph(opensource_text, styles['BodyCustom']))
    
    story.append(Spacer(1, 12))

def create_references(story, styles):
    story.append(Paragraph("<b>8. References and Further Reading</b>", styles['Heading1Custom']))
    
    story.append(Paragraph("<b>Foundational Papers</b>", styles['Heading2Custom']))
    
    refs_text = """
    Rabiner, L.R. (1977). "On the Use of Autocorrelation Analysis for Pitch Detection." IEEE Transactions on Acoustics, Speech, and Signal Processing.<br/><br/>
    
    de Cheveigne, A. and Kawahara, H. (2002). "YIN, a fundamental frequency estimator for speech and music." Journal of the Acoustical Society of America, 111(4), 1917-1930.<br/><br/>
    
    McLeod, P. and Wyvill, G. (2005). "A smarter way to find pitch." Proceedings of the International Computer Music Conference.<br/><br/>
    
    Talkin, D. (1995). "A Robust Algorithm for Pitch Tracking (RAPT)." In Kleijn, W.B. and Paliwal, K.K. (Eds.), Speech Coding and Synthesis. Elsevier.
    """
    story.append(Paragraph(refs_text, styles['BodyCustom']))
    
    story.append(Paragraph("<b>Deep Learning Methods</b>", styles['Heading2Custom']))
    
    dl_refs = """
    Kim, J.W., Salamon, J., Li, P., and Bello, J.P. (2018). "CREPE: A Convolutional Representation for Pitch Estimation." Proceedings of the IEEE International Conference on Acoustics, Speech and Signal Processing.<br/><br/>
    
    Stefani, M. and Turchet, L. (2022). "PESTO: Real-Time Pitch Estimation with Self-Supervised Learning." arXiv preprint.<br/><br/>
    
    Kroon, A. (2022). "Comparing Conventional Pitch Detection Algorithms with a Neural Network Approach." arXiv:2206.14357.
    """
    story.append(Paragraph(dl_refs, styles['BodyCustom']))
    
    story.append(Paragraph("<b>Recent Developments</b>", styles['Heading2Custom']))
    
    recent_refs = """
    SwiftF0 (2025). "Fast and Accurate Monophonic Pitch Detection." arXiv preprint.<br/><br/>
    
    "Improving Neural Pitch Estimation with SWIPE Kernels." arXiv:2507.11233 (2025).<br/><br/>
    
    "Pitch Contour Exploration Across Audio Domains." arXiv:2503.19161 (2025).
    """
    story.append(Paragraph(recent_refs, styles['BodyCustom']))

def main():
    # Output path
    output_path = "/home/z/my-project/download/pitch_detection_algorithms_guide.pdf"
    
    # Create document
    doc = SimpleDocTemplate(
        output_path,
        pagesize=letter,
        title="Pitch Detection Algorithms Guide",
        author='Z.ai',
        creator='Z.ai',
        subject='Comprehensive guide to audio pitch detection algorithms for VST development'
    )
    
    styles = create_styles()
    story = []
    
    # Build document sections
    create_cover_page(story, styles)
    create_introduction(story, styles)
    create_classical_algorithms(story, styles)
    create_frequency_domain(story, styles)
    create_deep_learning(story, styles)
    create_comparison_table(story, styles)
    create_vst_section(story, styles)
    create_industry_section(story, styles)
    create_references(story, styles)
    
    # Build PDF
    doc.build(story)
    print(f"PDF generated: {output_path}")

if __name__ == '__main__':
    main()
