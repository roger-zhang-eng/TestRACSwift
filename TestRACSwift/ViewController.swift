//
//  ViewController.swift
//  TestRACSwift
//
//  Created by RogerZ on 21/2/17.
//  Copyright © 2017 Roger Zhang. All rights reserved.
//

import UIKit
import ReactiveSwift
import ReactiveCocoa
import Result

class ViewController: UIViewController {

    private var viewModel: ViewModel!
    
    @IBOutlet var formView: FormView!
    
    let userService = UserService()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        // Initialize the interactive controls.
        
        
        viewModel = ViewModel(userService: userService)
        // Setup console messages.
        userService.requestSignal.observeValues {
            print("UserService.requestSignal: Username `\($0)`.")
        }
        
        viewModel.submit.completed.observeValues {
            print("ViewModel.submit: execution producer has completed.")
        }
        
        viewModel.email.signal.observeValues {
            print("ViewModel.email: Validation result - \($0 != nil ? "\($0!)" : "No validation has ever been performed.")")
        }
        
        viewModel.emailConfirmation.signal.observeValues {
            print("ViewModel.emailConfirmation: Validation result - \($0 != nil ? "\($0!)" : "No validation has ever been performed.")")
        }
        
        
        formView.emailField.text = viewModel.email.value
        formView.emailConfirmationField.text = viewModel.emailConfirmation.value
        formView.termsSwitch.isOn = false
        
        // Setup bindings with the interactive controls.
        viewModel.email <~ formView.emailField.reactive
            .continuousTextValues.skipNil()
        
        viewModel.emailConfirmation <~ formView.emailConfirmationField.reactive
            .continuousTextValues.skipNil()
        
        viewModel.termsAccepted <~ formView.termsSwitch.reactive
            .isOnValues
        
        // Setup bindings with the invalidation reason label.
        formView.reasonLabel.reactive.text <~ viewModel.reasons
        
        // Setup the Action binding with the submit button.
        formView.submitButton.reactive.pressed = CocoaAction(viewModel.submit)
        
        self.formView.setNeedsDisplay()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

}

typealias MutableStringProperty = MutableProperty<String>

final class ViewModel {
    struct FormError: Error {
        let reason: String
        
        static let invalidEmail = FormError(reason: "The address must end with `@gmail.com`.")
        static let mismatchEmail = FormError(reason: "The e-mail addresses do not match.")
        static let usernameUnavailable = FormError(reason: "The username has been taken.")
    }
    
    let email: MutableStringProperty
    //MutableValidatingProperty<String, FormError>
    let emailConfirmation: MutableStringProperty
    //MutableValidatingProperty<String, FormError>
    let termsAccepted: MutableProperty<Bool>
    
    let reasons: Signal<String, NoError>
    
    let submit: Action<(), (), FormError>
    
    init(userService: UserService) {
        email = MutableStringProperty("")
            
        /*    { input in
            return input.hasSuffix("@reactivecocoa.io") ? .success : .failure(.invalidEmail)
        }*/
        
        emailConfirmation = MutableStringProperty("")
        /*{ input, email in
            return input == email ? .success : .failure(.mismatchEmail)
        }*/
        
        termsAccepted = MutableProperty(false)
        
        
        
        // Aggregate latest failure contexts as a stream of strings.
        reasons = Property.combineLatest(email, emailConfirmation)
            .signal
            .debounce(0.1, on: QueueScheduler.main)
            .map { [$0, $1].flatMap { $0 }.joined(separator: "\n") }
        
        // A `Property` of the validated username.
        //
        // It outputs the valid username for the `Action` to work on, or `nil` if the form
        // is invalid and the `Action` would be disabled consequently.
        let validatedEmail = email //Property.combineLatest(email, emailConfirmation,
                                   //                 termsAccepted)
            //map { e, ec, t in e.value.flatMap { !ec.isFailure && t ? $0 : nil } }
        
        // The action to be invoked when the submit button is pressed.
        // It enables only if all the controls have passed their validations.
        submit = Action(input: validatedEmail) { (email: String) in
            let username = email.stripSuffix("@gmail.com")!
            
            return userService.canUseUsername(username)
                .promoteErrors(FormError.self)
                .attemptMap { Result<(), FormError>($0 ? () : nil, failWith: .usernameUnavailable) }
        }
    }
}

final class UserService {
    let (requestSignal, requestObserver) = Signal<String, NoError>.pipe()
    
    func canUseUsername(_ string: String) -> SignalProducer<Bool, NoError> {
        return SignalProducer { observer, disposable in
            self.requestObserver.send(value: string)
            observer.send(value: true)
            observer.sendCompleted()
        }
    }
}
