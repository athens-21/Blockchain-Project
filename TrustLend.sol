// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TrustLend is ReentrancyGuard, Ownable {
    IERC20 public immutable tdai;
    
    uint256 public constant ETH_PRICE_USD = 2500 * 1e18; // $2,500
    
    uint256 public loanIdCounter;
    uint256 public paymentIdCounter;

    uint256 public ltvPercent = 150;
    uint256 public liquidationThreshold = 120;
    uint256 public maxInterestRate = 50;
    uint256 public platformFeePercent = 1;
    uint256 public liquidationWarningDays = 3;
    
    address public feeCollector;

    enum LoanStatus { Pending, Active, Repaid, Liquidated }
    enum CollateralType { ETH }

    struct LoanRequest {
        address borrower;
        uint256 amount;
        uint256 interestRate;
        uint256 duration;
        uint256 collateral;
        CollateralType collateralType;
        uint256 timestamp;
    }

    struct ActiveLoan {
        address borrower;
        address lender;
        uint256 amount;
        uint256 interestRate;
        uint256 startTime;
        uint256 duration;
        uint256 collateral;
        CollateralType collateralType;
        LoanStatus status;
        bool warningIssued;
        uint256 paidAmount;
        uint256 lastPaymentTime;
    }

    struct Payment {
        uint256 paymentId;
        uint256 loanId;
        address payer;
        uint256 amount;
        uint256 timestamp;
        uint256 remainingDebt;
    }

    mapping(uint256 => LoanRequest) public loanRequests;
    uint256[] public pendingLoanIds;

    mapping(uint256 => ActiveLoan) public activeLoans;
    
    // บันทึกการชำระเงินแต่ละครั้ง
    mapping(uint256 => Payment) public payments;
    mapping(uint256 => uint256[]) public loanPayments; // loanId => paymentIds[]

    mapping(address => uint256[]) public myRequestedLoans;
    mapping(address => uint256[]) public myLentLoans;

    event LoanRequested(uint256 indexed id, address indexed borrower, uint256 amount, uint256 interest, uint256 duration, uint256 collateral, CollateralType collateralType);
    event LoanFunded(uint256 indexed id, address indexed lender);
    event LoanRepaid(uint256 indexed id, uint256 totalPaid, uint256 platformFee);
    event PaymentMade(uint256 indexed paymentId, uint256 indexed loanId, address indexed payer, uint256 amount, uint256 remaining, uint256 timestamp);
    event LoanLiquidated(uint256 indexed id, address indexed lender);
    event LiquidationWarning(uint256 indexed id, uint256 daysLeft);
    event ParametersUpdated(string parameter, uint256 newValue);

    constructor(address _tdai) Ownable(msg.sender) {
        require(_tdai != address(0), "Invalid TDAI address");
        tdai = IERC20(_tdai);
        feeCollector = msg.sender;
    }

    // === ADMIN FUNCTIONS ===
    function setLTVPercent(uint256 _ltv) external onlyOwner {
        require(_ltv >= 100 && _ltv <= 300, "LTV must be 100-300%");
        ltvPercent = _ltv;
        emit ParametersUpdated("LTV", _ltv);
    }

    function setLiquidationThreshold(uint256 _threshold) external onlyOwner {
        require(_threshold >= 100 && _threshold < ltvPercent, "Invalid threshold");
        liquidationThreshold = _threshold;
        emit ParametersUpdated("LiquidationThreshold", _threshold);
    }

    function setMaxInterestRate(uint256 _rate) external onlyOwner {
        require(_rate <= 100, "Max 100%");
        maxInterestRate = _rate;
        emit ParametersUpdated("MaxInterestRate", _rate);
    }

    function setPlatformFee(uint256 _fee) external onlyOwner {
        require(_fee <= 10, "Max 10%");
        platformFeePercent = _fee;
        emit ParametersUpdated("PlatformFee", _fee);
    }

    function setFeeCollector(address _collector) external onlyOwner {
        require(_collector != address(0), "Invalid address");
        feeCollector = _collector;
    }

    // === PRICE FUNCTIONS ===
    function getLatestPrice() public pure returns (uint256) {
        return ETH_PRICE_USD;
    }

    function calculateMinCollateral(uint256 amount) public view returns (uint256) {
        return (amount * ltvPercent * 1e18) / (ETH_PRICE_USD * 100);
    }

    // === LOAN FUNCTIONS ===
    function requestLoan(
        uint256 amount,
        uint256 interestRate,
        uint256 duration,
        CollateralType collateralType
    ) external payable nonReentrant {
        require(amount > 0, "Amount > 0");
        require(interestRate <= maxInterestRate, "Interest rate too high");
        require(duration >= 1 days && duration <= 365 days, "Duration 1-365 days");
        require(collateralType == CollateralType.ETH, "Only ETH supported");
        
        uint256 minCollateral = calculateMinCollateral(amount);
        require(msg.value >= minCollateral, "Insufficient ETH collateral");

        uint256 id = loanIdCounter++;
        loanRequests[id] = LoanRequest({
            borrower: msg.sender,
            amount: amount,
            interestRate: interestRate,
            duration: duration,
            collateral: msg.value,
            collateralType: collateralType,
            timestamp: block.timestamp
        });
        
        pendingLoanIds.push(id);
        myRequestedLoans[msg.sender].push(id);

        emit LoanRequested(id, msg.sender, amount, interestRate, duration, msg.value, collateralType);
    }

    function fundLoan(uint256 loanId) external nonReentrant {
        LoanRequest memory req = loanRequests[loanId];
        require(req.borrower != address(0), "Loan not exist");
        require(req.borrower != msg.sender, "Cannot fund own loan");

        require(tdai.transferFrom(msg.sender, req.borrower, req.amount), "Transfer failed");

        activeLoans[loanId] = ActiveLoan({
            borrower: req.borrower,
            lender: msg.sender,
            amount: req.amount,
            interestRate: req.interestRate,
            startTime: block.timestamp,
            duration: req.duration,
            collateral: req.collateral,
            collateralType: req.collateralType,
            status: LoanStatus.Active,
            warningIssued: false,
            paidAmount: 0,
            lastPaymentTime: block.timestamp
        });

        myLentLoans[msg.sender].push(loanId);
        _removePending(loanId);
        delete loanRequests[loanId];

        emit LoanFunded(loanId, msg.sender);
    }

    // ชำระเงิน - สามารถชำระบางส่วนหรือเต็มจำนวน
    function makePayment(uint256 loanId, uint256 paymentAmount) external nonReentrant {
        ActiveLoan storage loan = activeLoans[loanId];
        require(loan.status == LoanStatus.Active, "Not active");
        require(msg.sender == loan.borrower, "Not borrower");
        require(paymentAmount > 0, "Payment must be > 0");

        uint256 totalOwed = calculateTotalOwed(loanId);
        uint256 remainingDebt = totalOwed > loan.paidAmount ? totalOwed - loan.paidAmount : 0;
        
        require(remainingDebt > 0, "Loan already paid");
        require(paymentAmount <= remainingDebt, "Payment exceeds debt");

        // คำนวณค่าธรรมเนียม
        uint256 platformFee = (paymentAmount * platformFeePercent) / 100;
        uint256 lenderAmount = paymentAmount - platformFee;

        // โอนเงินให้ lender
        require(tdai.transferFrom(msg.sender, loan.lender, lenderAmount), "Lender payment failed");
        
        // โอนค่าธรรมเนียม
        if (platformFee > 0) {
            require(tdai.transferFrom(msg.sender, feeCollector, platformFee), "Fee payment failed");
        }

        // อัพเดทยอดชำระ
        loan.paidAmount += paymentAmount;
        loan.lastPaymentTime = block.timestamp;

        // คำนวณหนี้ที่เหลือหลังชำระ
        uint256 newRemaining = totalOwed > loan.paidAmount ? totalOwed - loan.paidAmount : 0;

        // บันทึกการชำระเงินครั้งนี้
        uint256 paymentId = paymentIdCounter++;
        payments[paymentId] = Payment({
            paymentId: paymentId,
            loanId: loanId,
            payer: msg.sender,
            amount: paymentAmount,
            timestamp: block.timestamp,
            remainingDebt: newRemaining
        });
        loanPayments[loanId].push(paymentId);

        emit PaymentMade(paymentId, loanId, msg.sender, paymentAmount, newRemaining, block.timestamp);

        // ถ้าชำระครบแล้ว
        if (newRemaining == 0) {
            loan.status = LoanStatus.Repaid;
            
            // คืนหลักประกัน ETH
            (bool success, ) = payable(loan.borrower).call{value: loan.collateral}("");
            require(success, "ETH return failed");

            emit LoanRepaid(loanId, totalOwed, (totalOwed * platformFeePercent) / 100);
        }
    }

    function liquidate(uint256 loanId) external nonReentrant {
        ActiveLoan storage loan = activeLoans[loanId];
        require(loan.status == LoanStatus.Active, "Not active");
        require(msg.sender == loan.lender, "Only lender");
        require(block.timestamp > loan.startTime + loan.duration, "Not due yet");

        loan.status = LoanStatus.Liquidated;
        
        // โอน ETH ให้ lender
        (bool success, ) = payable(loan.lender).call{value: loan.collateral}("");
        require(success, "Liquidation transfer failed");

        emit LoanLiquidated(loanId, msg.sender);
    }

    function issueWarning(uint256 loanId) external {
        ActiveLoan storage loan = activeLoans[loanId];
        require(loan.status == LoanStatus.Active, "Not active");
        require(!loan.warningIssued, "Warning already issued");
        
        uint256 timeLeft = (loan.startTime + loan.duration) - block.timestamp;
        uint256 daysLeft = timeLeft / 1 days;
        
        require(daysLeft <= liquidationWarningDays, "Not yet time for warning");
        
        loan.warningIssued = true;
        emit LiquidationWarning(loanId, daysLeft);
    }

    // === CALCULATION FUNCTIONS ===
    function calculateTotalOwed(uint256 loanId) public view returns (uint256) {
        ActiveLoan memory loan = activeLoans[loanId];
        if (loan.status != LoanStatus.Active) return 0;

        uint256 timePassed = block.timestamp - loan.startTime;
        if (timePassed > loan.duration) timePassed = loan.duration;

        uint256 interest = (loan.amount * loan.interestRate * timePassed) / (365 days * 100);
        return loan.amount + interest;
    }

    function calculateRemainingDebt(uint256 loanId) public view returns (uint256) {
        ActiveLoan memory loan = activeLoans[loanId];
        if (loan.status != LoanStatus.Active) return 0;

        uint256 totalOwed = calculateTotalOwed(loanId);
        return totalOwed > loan.paidAmount ? totalOwed - loan.paidAmount : 0;
    }

    function getHealthFactor(uint256 loanId) public view returns (uint256) {
        ActiveLoan memory loan = activeLoans[loanId];
        if (loan.status != LoanStatus.Active) return 0;

        uint256 remainingDebt = calculateRemainingDebt(loanId);
        if (remainingDebt == 0) return type(uint256).max;

        uint256 collateralValueTDAI = (loan.collateral * ETH_PRICE_USD) / 1e18;
        
        return (collateralValueTDAI * 100) / remainingDebt;
    }

    function isLoanHealthy(uint256 loanId) public view returns (bool) {
        uint256 healthFactor = getHealthFactor(loanId);
        return healthFactor >= liquidationThreshold;
    }

    function getLoansNeedingWarning() external view returns (uint256[] memory) {
        uint256 count = 0;
        uint256 warningTime = liquidationWarningDays * 1 days;
        
        for (uint256 i = 0; i < loanIdCounter; i++) {
            ActiveLoan memory loan = activeLoans[i];
            if (loan.status == LoanStatus.Active && !loan.warningIssued) {
                uint256 timeLeft = (loan.startTime + loan.duration) - block.timestamp;
                if (timeLeft <= warningTime) count++;
            }
        }
        
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < loanIdCounter; i++) {
            ActiveLoan memory loan = activeLoans[i];
            if (loan.status == LoanStatus.Active && !loan.warningIssued) {
                uint256 timeLeft = (loan.startTime + loan.duration) - block.timestamp;
                if (timeLeft <= warningTime) {
                    result[index++] = i;
                }
            }
        }
        
        return result;
    }

    // === PAYMENT HISTORY GETTERS ===
    function getLoanPaymentHistory(uint256 loanId) external view returns (Payment[] memory) {
        uint256[] memory paymentIds = loanPayments[loanId];
        Payment[] memory history = new Payment[](paymentIds.length);
        
        for (uint256 i = 0; i < paymentIds.length; i++) {
            history[i] = payments[paymentIds[i]];
        }
        
        return history;
    }

    function getPaymentCount(uint256 loanId) external view returns (uint256) {
        return loanPayments[loanId].length;
    }

    function getPayment(uint256 paymentId) external view returns (Payment memory) {
        return payments[paymentId];
    }

    // === GETTERS ===
    function getPendingLoans() external view returns (uint256[] memory) {
        return pendingLoanIds;
    }

    function getLoanRequest(uint256 id) external view returns (LoanRequest memory) {
        return loanRequests[id];
    }

    function getActiveLoan(uint256 id) external view returns (ActiveLoan memory) {
        return activeLoans[id];
    }

    function getMyRequestedLoans(address user) external view returns (uint256[] memory) {
        return myRequestedLoans[user];
    }

    function getMyLentLoans(address user) external view returns (uint256[] memory) {
        return myLentLoans[user];
    }

    function getParameters() external view returns (
        uint256 ltv,
        uint256 liqThreshold,
        uint256 maxRate,
        uint256 platformFee,
        uint256 warningDays
    ) {
        return (ltvPercent, liquidationThreshold, maxInterestRate, platformFeePercent, liquidationWarningDays);
    }

    // === INTERNAL ===
    function _removePending(uint256 loanId) internal {
        for (uint i = 0; i < pendingLoanIds.length; i++) {
            if (pendingLoanIds[i] == loanId) {
                pendingLoanIds[i] = pendingLoanIds[pendingLoanIds.length - 1];
                pendingLoanIds.pop();
                break;
            }
        }
    }

    receive() external payable {}
}