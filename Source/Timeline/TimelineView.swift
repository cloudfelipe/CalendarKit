import UIKit
import Neon
import DateToolsSwift

public protocol TimelineViewDelegate: class {
    func timelineView(_ timelineView: TimelineView, didLongPressAt hour: Int)
    func timelineView(_ timelineView: TimelineView, didLongPressAt time: (hour: Int, minute: Int))
}

public class TimelineView: UIView, ReusableView {
    
    public weak var delegate: TimelineViewDelegate?
    
    public weak var eventViewDelegate: EventViewDelegate?
    
    public var date = Date() {
        didSet {
            setNeedsLayout()
        }
    }
    
    var currentTime: Date {
        return Date()
    }
    
    var eventViews = [EventView]()
    public var layoutAttributes = [EventLayoutAttributes]() {
        didSet {
            recalculateEventLayout()
            prepareEventViews()
            setNeedsLayout()
        }
    }
    var pool = ReusePool<EventView>()
    
    var firstEventYPosition: CGFloat? {
        return layoutAttributes.sorted{$0.frame.origin.y < $1.frame.origin.y}
            .first?.frame.origin.y
    }
    
    lazy var nowLine: CurrentTimeIndicator = CurrentTimeIndicator()
    
    var style = TimelineStyle()
    
    var verticalDiff: CGFloat {
        return style.timeViewHeight
    }
    var verticalInset: CGFloat = 10
    var leftInset: CGFloat = 53
    
    var horizontalEventInset: CGFloat = 3
    
    public var fullHeight: CGFloat {
        return verticalInset * 2 + verticalDiff * 24
    }
    
    var calendarWidth: CGFloat {
        return bounds.width - leftInset
    }
    
    var is24hClock = true {
        didSet {
            setNeedsDisplay()
        }
    }
    
    init() {
        super.init(frame: .zero)
        frame.size.height = fullHeight
        configure()
    }
    
    var times: [String] {
        return is24hClock ? _24hTimes : _12hTimes
    }
    
    fileprivate lazy var _12hTimes: [String] = Generator.timeStrings12H()
    fileprivate lazy var _24hTimes: [String] = Generator.timeStrings24H()
    
    fileprivate lazy var longPressGestureRecognizer: UILongPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(longPress(_:)))
    
    var isToday: Bool {
        return date.isToday
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        configure()
    }
    
    func configure() {
        contentScaleFactor = 1
        layer.contentsScale = 1
        contentMode = .redraw
        backgroundColor = .white
        addSubview(nowLine)
        
        // Add long press gesture recognizer
        addGestureRecognizer(longPressGestureRecognizer)
    }
    
    @objc func longPress(_ gestureRecognizer: UILongPressGestureRecognizer) {
        if (gestureRecognizer.state == .began) {
            // Get timeslot of gesture location
            let pressedLocation = gestureRecognizer.location(in: self)
            let percentOfHeight = (pressedLocation.y - verticalInset) / (bounds.height - (verticalInset * 2))
            
            //Converts Hundredths of an Hour to Minutes
            let wholeFractionOfHour = Double(24 * percentOfHeight) //The fraction of hour to be calculated
            let intHour = Double(Int(wholeFractionOfHour)) //Extracts the Integer Part
            let fractionOfHour = abs(wholeFractionOfHour - intHour) //Calculates only the fraction without integer part
            let fractionOfHourRnd = round(fractionOfHour*100) / 100 //Rounds the fraction
            let ruleOf3 = fractionOfHourRnd*59/0.98 //Calculates the minute from Fraction of Hour using a rule of 3. *http://www.aurorak12.org/hr/timecard/Conversion.pdf*
            let minuteExtract = Int(ruleOf3) //Rounds the calculated minute
            
            delegate?.timelineView(self, didLongPressAt: (hour: Int(wholeFractionOfHour), minute: minuteExtract))
        }
    }
    
    public func updateStyle(_ newStyle: TimelineStyle) {
        style = newStyle.copy() as! TimelineStyle
        nowLine.updateStyle(style.timeIndicator)
        
        switch style.dateStyle {
        case .twelveHour:
            is24hClock = false
            break
        case .twentyFourHour:
            is24hClock = true
            break
        default:
            is24hClock = Locale.autoupdatingCurrent.uses24hClock()
            break
        }
        
        backgroundColor = style.backgroundColor
        setNeedsDisplay()
    }
    
    override public func draw(_ rect: CGRect) {
        super.draw(rect)
        
        var hourToRemoveIndex = -1
        
        if isToday {
            let minute = currentTime.component(.minute)
            hourToRemoveIndex = currentTime.component(.hour)
            
            if minute > 55 {
                hourToRemoveIndex += 1
            }
        }
        
        let mutableParagraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        mutableParagraphStyle.lineBreakMode = .byWordWrapping
        mutableParagraphStyle.alignment = .right
        let paragraphStyle = mutableParagraphStyle.copy() as! NSParagraphStyle
        
        let attributes = [NSAttributedStringKey.paragraphStyle: paragraphStyle,
                          NSAttributedStringKey.foregroundColor: self.style.timeColor,
                          NSAttributedStringKey.font: style.font] as [NSAttributedStringKey : Any]
        
        for (i, time) in times.enumerated() {
            let iFloat = CGFloat(i)
            let context = UIGraphicsGetCurrentContext()
            context!.interpolationQuality = .none
            context?.saveGState()
            context?.setStrokeColor(self.style.lineColor.cgColor)
            context?.setLineWidth(onePixel)
            context?.translateBy(x: 0, y: 0.5)
            let x: CGFloat = 53
            let y = verticalInset + iFloat * verticalDiff
            context?.beginPath()
            context?.move(to: CGPoint(x: x, y: y))
            context?.addLine(to: CGPoint(x: (bounds).width, y: y))
            context?.strokePath()
            context?.restoreGState()
            
            //Hide time label if current time line overlaps it
            var removeHour = false
            var remove30Min = false
            var remove15Min = false
            var remove45Min = false
            if i == hourToRemoveIndex {
                let minute = currentTime.component(.minute)
                switch minute {
                case 0...5, 55...60:
                    removeHour = true
                    break
                case 10...20:
                    remove15Min = true
                    break
                case 25...35:
                    remove30Min = true
                    break
                case 40...50:
                    remove45Min = true
                    break
                default:
                    break
                }
            }
            
            let fontSize = style.font.pointSize
            
            // line to be added for 30 min interval
            let subLineContext = UIGraphicsGetCurrentContext()
            subLineContext!.interpolationQuality = .none
            subLineContext?.saveGState()
            subLineContext?.setStrokeColor(UIColor.clear.cgColor)
            subLineContext?.setLineWidth(1)
            subLineContext?.translateBy(x: 0, y: 0)
            let halfHourX: CGFloat = 53
            let halfHourY = (verticalInset + iFloat * verticalDiff) + (verticalDiff/2)
            subLineContext?.beginPath()
            subLineContext?.move(to: CGPoint(x: halfHourX, y: halfHourY))
            subLineContext?.addLine(to: CGPoint(x: (bounds).width, y: halfHourY))
            subLineContext?.strokePath()
            
            if !removeHour {
                let timeRect = CGRect(x: 2, y: iFloat * verticalDiff + verticalInset - 7,
                                      width: leftInset - 8, height: fontSize + 2)
                let timeString = NSString(string: time)
                timeString.draw(in: timeRect, withAttributes: attributes)
            }
            
            if !remove30Min {
                //add half hour time string
                let halfHourTimeRect = CGRect(x: 2, y: (iFloat * verticalDiff + verticalInset - 7) + (verticalDiff/2),
                                              width: leftInset - 8, height: fontSize + 2)
                let halfHourTimeString = NSString(string: "30")
                halfHourTimeString.draw(in: halfHourTimeRect, withAttributes: attributes)
            }
            
            if !remove15Min {
                let min15TimeRect = CGRect(x: 2, y: (iFloat * verticalDiff + verticalInset - 7) + (verticalDiff/4),
                                           width: leftInset - 8, height: fontSize + 2)
                let min15TimeString = NSString(string: "15")
                min15TimeString.draw(in: min15TimeRect, withAttributes: attributes)
            }
            
            if !remove45Min {
                let min45TimeRect = CGRect(x: 2,
                                           y: (iFloat * verticalDiff + verticalInset - 7) + (verticalDiff/2) + (verticalDiff/4),
                                           width: leftInset - 8, height: fontSize + 2)
                let min45TimeString = NSString(string: "45")
                min45TimeString.draw(in: min45TimeRect, withAttributes: attributes)
            }
        }
    }
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        recalculateEventLayout()
        layoutEvents()
        layoutNowLine()
    }
    
    func layoutNowLine() {
        if !isToday {
            nowLine.alpha = 0
        } else {
            bringSubview(toFront: nowLine)
            nowLine.alpha = 1
            let size = CGSize(width: bounds.size.width, height: 20)
            let rect = CGRect(origin: CGPoint.zero, size: size)
            nowLine.date = currentTime
            nowLine.frame = rect
            nowLine.center.y = dateToY(currentTime)
        }
    }
    
    func layoutEvents() {
        if eventViews.isEmpty {return}
        
        for (idx, attributes) in layoutAttributes.enumerated() {
            let descriptor = attributes.descriptor
            let eventView = eventViews[idx]
            eventView.frame = attributes.frame
            eventView.updateWithDescriptor(event: descriptor)
        }
    }
    
    func recalculateEventLayout() {
        let sortedEvents = layoutAttributes.sorted { (attr1, attr2) -> Bool in
            let start1 = attr1.descriptor.startDate
            let start2 = attr2.descriptor.startDate
            return start1.isEarlier(than: start2)
        }
        
        var groupsOfEvents = [[EventLayoutAttributes]]()
        var overlappingEvents = [EventLayoutAttributes]()
        
        for event in sortedEvents {
            if overlappingEvents.isEmpty {
                overlappingEvents.append(event)
                continue
            }
            
            let longestEvent = overlappingEvents.sorted { (attr1, attr2) -> Bool in
                let period1 = attr1.descriptor.datePeriod.seconds
                let period2 = attr2.descriptor.datePeriod.seconds
                return period1 > period2
                }
                .first!
            
            let lastEvent = overlappingEvents.last!
            if longestEvent.descriptor.datePeriod.overlaps(with: event.descriptor.datePeriod) ||
                lastEvent.descriptor.datePeriod.overlaps(with: event.descriptor.datePeriod) {
                overlappingEvents.append(event)
                continue
            } else {
                groupsOfEvents.append(overlappingEvents)
                overlappingEvents.removeAll()
                overlappingEvents.append(event)
            }
        }
        
        groupsOfEvents.append(overlappingEvents)
        overlappingEvents.removeAll()
        
        for overlappingEvents in groupsOfEvents {
            let totalCount = CGFloat(overlappingEvents.count)
            for (index, event) in overlappingEvents.enumerated() {
                let startY = dateToY(event.descriptor.datePeriod.beginning!)
                let endY = dateToY(event.descriptor.datePeriod.end!)
                let floatIndex = CGFloat(index)
                let x = leftInset + floatIndex / totalCount * calendarWidth
                let equalWidth = calendarWidth / totalCount
                event.frame = CGRect(x: x, y: startY, width: equalWidth, height: endY - startY)
            }
        }
    }
    
    func prepareEventViews() {
        pool.enqueue(views: eventViews)
        eventViews.removeAll()
        for _ in 0...layoutAttributes.endIndex {
            let newView = pool.dequeue()
            newView.delegate = eventViewDelegate
            if newView.superview == nil {
                addSubview(newView)
            }
            eventViews.append(newView)
        }
    }
    
    func prepareForReuse() {
        pool.enqueue(views: eventViews)
        eventViews.removeAll()
        setNeedsDisplay()
    }
    
    // MARK: - Helpers
    
    fileprivate var onePixel: CGFloat {
        return 1 / UIScreen.main.scale
    }
    
    fileprivate func dateToY(_ date: Date) -> CGFloat {
        if date.dateOnly() > self.date.dateOnly() {
            // Event ending the next day
            return 24 * verticalDiff + verticalInset
        } else if date.dateOnly() < self.date.dateOnly() {
            // Event starting the previous day
            return verticalInset
        } else {
            let hourY = CGFloat(date.hour) * verticalDiff + verticalInset
            let minuteY = CGFloat(date.minute) * verticalDiff / 60
            return hourY + minuteY
        }
    }
}
